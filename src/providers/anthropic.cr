require "json"
require "http/client"
require "./types"

module CrystalClaw
  module Providers
    # Anthropic Messages API provider
    class AnthropicProvider < LLMProvider
      @api_key : String
      @api_base : String
      @default_model_name : String
      @read_timeout : Int32

      def initialize(@api_key, @api_base = "https://api.anthropic.com", @default_model_name = "claude-sonnet-4-20250514", @read_timeout = 120)
      end

      def default_model : String
        @default_model_name
      end

      def chat(messages : Array(Message), tools : Array(ToolDefinition), model : String, options : Hash(String, JSON::Any)? = nil) : LLMResponse
        model = @default_model_name if model.empty?

        # Extract system message
        system_text = ""
        user_messages = messages.reject do |m|
          if m.role == "system"
            system_text = m.content || ""
            true
          else
            false
          end
        end

        body = build_request(system_text, user_messages, tools, model, options)

        headers = HTTP::Headers{
          "Content-Type"      => "application/json",
          "x-api-key"         => @api_key,
          "anthropic-version" => "2023-06-01",
        }

        url = "#{@api_base.rstrip('/')}/v1/messages"
        uri = URI.parse(url)
        client = HTTP::Client.new(uri)
        client.read_timeout = @read_timeout.seconds
        client.connect_timeout = 30.seconds

        begin
          response = client.post(uri.request_target, headers: headers, body: body)
          handle_response(response, model)
        rescue ex : IO::TimeoutError
          raise FailoverError.new(FailoverReason::Timeout, "anthropic", model, 0, ex)
        rescue ex : FailoverError
          raise ex
        rescue ex
          raise FailoverError.new(FailoverReason::Unknown, "anthropic", model, 0, ex)
        ensure
          client.close
        end
      end

      private def build_request(system_text : String, messages : Array(Message), tools : Array(ToolDefinition), model : String, options : Hash(String, JSON::Any)?) : String
        max_tokens = 8192
        if opts = options
          if mt = opts["max_tokens"]?
            max_tokens = mt.as_i
          end
        end

        JSON.build do |json|
          json.object do
            json.field "model", model
            json.field "max_tokens", max_tokens

            unless system_text.empty?
              json.field "system", system_text
            end

            json.field "messages" do
              json.array do
                messages.each do |msg|
                  json.object do
                    # Map roles: tool -> user (with tool_result content)
                    role = msg.role == "tool" ? "user" : msg.role
                    json.field "role", role

                    if msg.role == "tool"
                      # Anthropic expects tool results in a specific format
                      json.field "content" do
                        json.array do
                          json.object do
                            json.field "type", "tool_result"
                            json.field "tool_use_id", msg.tool_call_id || ""
                            json.field "content", msg.content || ""
                          end
                        end
                      end
                    elsif tc = msg.tool_calls
                      unless tc.empty?
                        # Assistant message with tool use
                        json.field "content" do
                          json.array do
                            # Include text content if present
                            if text = msg.content
                              unless text.empty?
                                json.object do
                                  json.field "type", "text"
                                  json.field "text", text
                                end
                              end
                            end
                            tc.each do |call|
                              json.object do
                                json.field "type", "tool_use"
                                json.field "id", call.id
                                json.field "name", call.function.try(&.name) || ""
                                json.field "input" do
                                  args = call.function.try(&.arguments) || "{}"
                                  json.raw(args)
                                end
                              end
                            end
                          end
                        end
                      end
                    else
                      json.field "content", msg.content || ""
                    end
                  end
                end
              end
            end

            unless tools.empty?
              json.field "tools" do
                json.array do
                  tools.each do |tool|
                    json.object do
                      json.field "name", tool.function.name
                      json.field "description", tool.function.description
                      json.field "input_schema" do
                        json.raw(tool.function.parameters.to_json)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end

      private def handle_response(response : HTTP::Client::Response, model : String) : LLMResponse
        unless response.success?
          reason = classify_error(response.status_code)
          raise FailoverError.new(reason, "anthropic", model, response.status_code,
            Exception.new(response.body[0, 500]))
        end

        data = JSON.parse(response.body)
        content_blocks = data["content"]?.try(&.as_a?) || [] of JSON::Any

        text_content = ""
        tool_calls = [] of ToolCall

        content_blocks.each do |block|
          block_type = block["type"]?.try(&.as_s?) || ""
          case block_type
          when "text"
            text_content += block["text"]?.try(&.as_s?) || ""
          when "tool_use"
            id = block["id"]?.try(&.as_s?) || ""
            name = block["name"]?.try(&.as_s?) || ""
            input = block["input"]?.try(&.to_json) || "{}"
            tool_calls << ToolCall.new(
              id: id,
              type: "function",
              function: FunctionCall.new(name: name, arguments: input)
            )
          end
        end

        stop_reason = data["stop_reason"]?.try(&.as_s?) || "end_turn"
        finish_reason = case stop_reason
                        when "tool_use"   then "tool_calls"
                        when "end_turn"   then "stop"
                        when "max_tokens" then "length"
                        else                   stop_reason
                        end

        usage_info = nil
        if u = data["usage"]?
          usage_info = UsageInfo.new(
            prompt_tokens: u["input_tokens"]?.try(&.as_i?) || 0,
            completion_tokens: u["output_tokens"]?.try(&.as_i?) || 0,
            total_tokens: (u["input_tokens"]?.try(&.as_i?) || 0) + (u["output_tokens"]?.try(&.as_i?) || 0),
          )
        end

        LLMResponse.new(
          content: text_content,
          tool_calls: tool_calls,
          finish_reason: finish_reason,
          usage: usage_info
        )
      end

      private def classify_error(status : Int32) : FailoverReason
        case status
        when 401, 403 then FailoverReason::Auth
        when 429      then FailoverReason::RateLimit
        when 402      then FailoverReason::Billing
        when 408, 504 then FailoverReason::Timeout
        when 400, 422 then FailoverReason::Format
        when 503, 529 then FailoverReason::Overloaded
        else               FailoverReason::Unknown
        end
      end
    end
  end
end
