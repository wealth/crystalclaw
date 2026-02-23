require "json"
require "db"
require "./base"
require "../config/config"
require "../memory/base"

module CrystalClaw
  module Tools
    # ── Config Management Tools ──

    class UpdateConfigTool < Tool
      @store : Memory::Store

      def initialize(@store)
      end

      def name : String
        "update_config"
      end

      def description : String
        "Update a configuration key in the database. Uses dot-notation paths (e.g. 'channels.telegram.token', 'providers.openrouter.api_key', 'heartbeat.enabled'). The value is parsed as JSON if valid, otherwise treated as a string."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({
          "type": "object",
          "properties": {
            "key": {
              "type": "string",
              "description": "Dot-notation path to the config key (e.g. 'channels.telegram.token', 'providers.openrouter.api_key', 'heartbeat.enabled')"
            },
            "value": {
              "type": "string",
              "description": "New value for the key. Will be parsed as JSON if valid (for booleans, numbers, arrays), otherwise treated as a string."
            }
          },
          "required": ["key", "value"]
        })).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        key = args["key"]?.try(&.as_s?) || return ToolResult.error("Missing 'key' argument")
        value_str = args["value"]?.try(&.as_s?) || return ToolResult.error("Missing 'value' argument")

        # Load current config JSON from store
        # Here we just re-build the whole json config to set a nested value, then save everything.
        # But wait, with dot paths we can just set the single value natively!
        parsed_value = begin
          JSON.parse(value_str)
        rescue
          JSON::Any.new(value_str)
        end

        begin
          @store.set_config(key, parsed_value.to_json)
        rescue ex
          return ToolResult.error("Failed to set config key '#{key}': #{ex.message}")
        end

        ToolResult.success("Successfully updated config key '#{key}' to: #{parsed_value.to_json}. Use the reinitialize tool to apply changes.")
      end
    end

    class ReinitializeTool < Tool
      @reinit_callback : Proc(String)

      def initialize(&@reinit_callback : -> String)
      end

      def name : String
        "reinitialize"
      end

      def description : String
        "Reinitialize the agent by reloading configuration from the database. Use this after updating config keys to apply changes. The agent will reload its config, rebuild its tool registry, and report the new state."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({ "type": "object", "properties": {}, "required": [] })).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        begin
          result = @reinit_callback.call
          ToolResult.success(result)
        rescue ex
          ToolResult.error("Reinitialization failed: #{ex.message}")
        end
      end
    end

    # ── Prompt Update Tools (one per prompt file) ──

    macro define_prompt_tool(class_name, tool_name, store_key, description)
      class {{class_name}} < Tool
        @store : Memory::Store

        def initialize(@store)
        end

        def name : String
          {{tool_name}}
        end

        def description : String
          {{description}}
        end

        def parameters : Hash(String, JSON::Any)
          JSON.parse(%({
            "type": "object",
            "properties": {
              "content": {
                "type": "string",
                "description": "The new markdown content. This replaces the entire file."
              }
            },
            "required": ["content"]
          })).as_h
        end

        def execute(args : Hash(String, JSON::Any)) : ToolResult
          content = args["content"]?.try(&.as_s?) || return ToolResult.error("Missing 'content' argument")
          begin
            @store.set({{store_key}}, content)
            ToolResult.success("Successfully updated #{{{store_key}}} (#{content.bytesize} bytes). Changes take effect on the next message.")
          rescue ex
            ToolResult.error("Failed to update #{{{store_key}}}: #{ex.message}")
          end
        end
      end
    end

    define_prompt_tool(
      UpdateIdentityTool, "update_identity", "IDENTITY.md",
      "Update the agent's identity prompt (IDENTITY.md). This defines who the agent is, its name, and core traits."
    )

    define_prompt_tool(
      UpdateSoulTool, "update_soul", "SOUL.md",
      "Update the agent's soul prompt (SOUL.md). This defines the agent's deeper personality and values."
    )

    define_prompt_tool(
      UpdateAgentTool, "update_agent", "AGENT.md",
      "Update the agent behavior prompt (AGENT.md). This defines behavior guidelines, rules, and how the agent should act."
    )

    define_prompt_tool(
      UpdateUserTool, "update_user", "USER.md",
      "Update the user preferences prompt (USER.md). This stores user preferences like language, response style, and personal details."
    )

    define_prompt_tool(
      UpdateMemoryTool, "update_memory", "memory/MEMORY.md",
      "Update the agent's long-term memory (memory/MEMORY.md). This stores important facts and information across sessions."
    )
  end
end
