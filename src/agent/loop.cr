require "json"
require "./context"
require "./instance"
require "./registry"
require "../bus/bus"
require "../config/config"
require "../logger/logger"
require "../providers/types"
require "../providers/factory"
require "../routing/route"
require "../tools/base"
require "../tools/filesystem"
require "../tools/edit"
require "../tools/shell"
require "../tools/web"
require "../tools/message"

module CrystalClaw
  module Agent
    class AgentLoop
      @bus : Bus::MessageBus
      @cfg : Config
      @registry : Registry
      @provider : Providers::LLMProvider
      @running : Atomic(Int32)

      def initialize(@cfg, @bus, @provider)
        @registry = Registry.new(@cfg)
        @running = Atomic(Int32).new(0)

        # Register shared tools to all agents
        register_shared_tools
      end

      def register_tool(tool : Tools::Tool)
        @registry.register_tool_to_all(tool)
      end

      def get_startup_info : Hash(String, Int32)
        agent = @registry.get_default_agent
        {
          "tools_count" => agent.tools.size,
        }
      end

      # One-shot: process a message directly, return response
      def process_direct(content : String, session_key : String) : String
        agent = @registry.get_default_agent
        run_agent_loop(agent, content, session_key, "cli", "direct",
          enable_summary: false, no_history: false)
      end

      # Process a heartbeat (no history, independent)
      def process_heartbeat(content : String, channel : String, chat_id : String) : String
        agent = @registry.get_default_agent
        run_agent_loop(agent, content, "heartbeat", channel, chat_id,
          enable_summary: false, no_history: true)
      end

      # Run the gateway message loop
      def run
        @running.set(1)
        while @running.get == 1
          msg = @bus.consume_inbound
          if msg
            begin
              response = process_message(msg)
              unless response.empty?
                # Check if message tool already sent
                already_sent = check_message_sent
                unless already_sent
                  @bus.publish_outbound(Bus::OutboundMessage.new(
                    channel: msg.channel,
                    chat_id: msg.chat_id,
                    content: response,
                    metadata: msg.metadata
                  ))
                end
              end
            rescue ex
              Logger.error("agent", "Error processing message: #{ex.message}")
              @bus.publish_outbound(Bus::OutboundMessage.new(
                channel: msg.channel,
                chat_id: msg.chat_id,
                content: "Error: #{ex.message}",
                metadata: msg.metadata
              ))
            end
          else
            sleep 50.milliseconds # small sleep to avoid busy-waiting
          end
        end
      end

      def stop
        @running.set(0)
      end

      private def register_shared_tools
        # Web tools
        web_cfg = @cfg.tools.web
        search_tool = Tools::WebSearchTool.new(
          brave_api_key: web_cfg.brave.api_key,
          brave_max_results: web_cfg.brave.max_results,
          brave_enabled: web_cfg.brave.enabled,
          ddg_max_results: web_cfg.duckduckgo.max_results,
          ddg_enabled: web_cfg.duckduckgo.enabled
        )
        @registry.register_tool_to_all(search_tool)
        @registry.register_tool_to_all(Tools::WebFetchTool.new)

        # Message tool
        msg_tool = Tools::MessageTool.new
        msg_tool.set_send_callback do |channel, chat_id, content|
          @bus.publish_outbound(Bus::OutboundMessage.new(
            channel: channel,
            chat_id: chat_id,
            content: content
          ))
        end
        @registry.register_tool_to_all(msg_tool)
      end

      private def process_message(msg : Bus::InboundMessage) : String
        Logger.info("agent", "Processing message from #{msg.channel}:#{msg.sender_id}")

        # Route to determine session key
        route = Routing.resolve(msg.channel, msg.sender_id, msg.chat_id, msg.metadata)
        agent = @registry.get_agent(route.agent_id) || @registry.get_default_agent

        # Set context on contextual tools
        set_tool_contexts(agent, msg.channel, msg.chat_id)

        run_agent_loop(agent, msg.content, route.session_key, msg.channel, msg.chat_id,
          enable_summary: true, no_history: false)
      end

      private def set_tool_contexts(agent : Instance, channel : String, chat_id : String)
        agent.tools.list.each do |tool|
          if tool.responds_to?(:set_context)
            tool.set_context(channel, chat_id)
          end
        end
      end

      private def check_message_sent : Bool
        agent = @registry.get_default_agent
        if tool = agent.tools.get("message")
          if mt = tool.as?(Tools::MessageTool)
            return mt.sent_in_round?
          end
        end
        false
      end

      private def reset_message_tool
        @registry.list_agent_ids.each do |id|
          if agent = @registry.get_agent(id)
            if tool = agent.tools.get("message")
              if mt = tool.as?(Tools::MessageTool)
                mt.reset_round
              end
            end
          end
        end
      end

      # ── Core agent loop — the heart of the system ──

      private def run_agent_loop(
        agent : Instance,
        user_message : String,
        session_key : String,
        channel : String,
        chat_id : String,
        enable_summary : Bool = false,
        no_history : Bool = false,
      ) : String
        # Reset message tool state
        reset_message_tool

        # Build system prompt
        system_prompt = agent.context_builder.build_system_prompt

        # Load history (or start fresh)
        messages = if no_history
                     [] of Providers::Message
                   else
                     agent.session_manager.load_history(session_key)
                   end

        # Prepend system message
        all_messages = [Providers::Message.new(role: "system", content: system_prompt)]
        all_messages.concat(messages)

        # Add user message
        user_msg = Providers::Message.new(role: "user", content: user_message)
        all_messages << user_msg

        # Save user message to session
        unless no_history
          agent.session_manager.append_message(session_key, user_msg)
        end

        # Get tool definitions
        tool_defs = agent.tools.to_definitions

        # Build options
        options = {
          "temperature" => JSON::Any.new(agent.temperature),
          "max_tokens"  => JSON::Any.new(agent.max_tokens.to_i64),
        }

        # Tool loop
        iterations = 0
        max_iterations = agent.max_tool_iterations
        final_response = ""

        loop do
          iterations += 1
          if iterations > max_iterations
            Logger.warn("agent", "Max tool iterations (#{max_iterations}) reached")
            final_response = "I've reached the maximum number of tool iterations. Here's what I have so far:\n\n#{final_response}"
            break
          end

          Logger.debug("agent", "LLM call ##{iterations}, messages=#{all_messages.size}, tools=#{tool_defs.size}")

          # Call LLM
          begin
            response = @provider.chat(all_messages, tool_defs, agent.model, options)
          rescue ex : Providers::FailoverError
            Logger.error("agent", "LLM error: #{ex.message}")
            final_response = "Error communicating with AI provider: #{ex.message}"
            break
          rescue ex
            Logger.error("agent", "Unexpected error: #{ex.message}")
            final_response = "Unexpected error: #{ex.message}"
            break
          end

          # Log usage
          if usage = response.usage
            Logger.debug("agent", "Usage: prompt=#{usage.prompt_tokens} completion=#{usage.completion_tokens} total=#{usage.total_tokens}")
          end

          # Check for tool calls
          if response.tool_calls.empty?
            # No tool calls — we have our final response
            final_response = response.content
            # Save assistant response to history
            assistant_msg = Providers::Message.new(role: "assistant", content: final_response)
            unless no_history
              agent.session_manager.append_message(session_key, assistant_msg)
            end
            break
          end

          # Process tool calls
          Logger.info("agent", "Executing #{response.tool_calls.size} tool call(s)")

          # Add assistant message with tool calls
          assistant_msg = Providers::Message.new(
            role: "assistant",
            content: response.content.empty? ? nil : response.content,
            tool_calls: response.tool_calls
          )
          all_messages << assistant_msg
          unless no_history
            agent.session_manager.append_message(session_key, assistant_msg)
          end

          # Execute each tool call
          response.tool_calls.each do |tc|
            func = tc.function
            next unless func

            tool = agent.tools.get(func.name)
            unless tool
              tool_result = Tools::ToolResult.error("Unknown tool: #{func.name}")
              tool_msg = Providers::Message.new(
                role: "tool",
                content: tool_result.content,
                tool_call_id: tc.id
              )
              all_messages << tool_msg
              unless no_history
                agent.session_manager.append_message(session_key, tool_msg)
              end
              next
            end

            # Parse arguments
            args = begin
              JSON.parse(func.arguments).as_h
            rescue
              {} of String => JSON::Any
            end

            Logger.info("agent", "Tool: #{func.name}(#{args.values.join(", ")})")

            # Execute tool
            begin
              result = tool.execute(args)
            rescue ex
              result = Tools::ToolResult.error("Tool error: #{ex.message}")
            end

            if result.error
              Logger.warn("agent", "Tool #{func.name} error: #{result.content[0, 200]}")
            else
              Logger.debug("agent", "Tool #{func.name} success: #{result.content[0, 100]}")
            end

            # Add tool result as message
            tool_msg = Providers::Message.new(
              role: "tool",
              content: result.content,
              tool_call_id: tc.id
            )
            all_messages << tool_msg
            unless no_history
              agent.session_manager.append_message(session_key, tool_msg)
            end
          end
        end

        if final_response.empty?
          final_response = "I've completed processing but have no response to give."
        end

        final_response
      end
    end
  end
end
