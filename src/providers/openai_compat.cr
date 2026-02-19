require "json"
require "http/client"
require "./types"

module CrystalClaw
  module Providers
    # OpenAI-compatible provider — works with OpenRouter, OpenAI, Zhipu, Groq, vLLM, Gemini, DeepSeek
    class OpenAICompatProvider < LLMProvider
      @api_key : String
      @api_base : String
      @default_model_name : String
      @read_timeout : Int32

      def initialize(@api_key, @api_base = "https://openrouter.ai/api/v1", @default_model_name = "openrouter/auto", @read_timeout = 120)
      end

      def default_model : String
        @default_model_name
      end

      def chat(messages : Array(Message), tools : Array(ToolDefinition), model : String, options : Hash(String, JSON::Any)? = nil) : LLMResponse
        model = @default_model_name if model.empty?
        body = build_request(messages, tools, model, options)

        headers = HTTP::Headers{
          "Content-Type"  => "application/json",
          "Authorization" => "Bearer #{@api_key}",
        }

        url = "#{@api_base.rstrip('/')}/chat/completions"
        uri = URI.parse(url)

        client = HTTP::Client.new(uri)
        client.read_timeout = @read_timeout.seconds
        client.connect_timeout = 30.seconds

        begin
          response = client.post(uri.request_target, headers: headers, body: body)
          handle_response(response, model)
        rescue ex : IO::TimeoutError
          raise FailoverError.new(FailoverReason::Timeout, "openai_compat", model, 0, ex)
        rescue ex
          raise FailoverError.new(FailoverReason::Unknown, "openai_compat", model, 0, ex)
        ensure
          client.close
        end
      end

      private def build_request(messages : Array(Message), tools : Array(ToolDefinition), model : String, options : Hash(String, JSON::Any)?) : String
        req = JSON.build do |json|
          json.object do
            json.field "model", model
            json.field "messages" do
              json.array do
                messages.each do |msg|
                  json.object do
                    json.field "role", msg.role
                    if content = msg.content
                      json.field "content", content
                    end
                    if tc = msg.tool_calls
                      unless tc.empty?
                        json.field "tool_calls" do
                          json.array do
                            tc.each do |call|
                              json.object do
                                json.field "id", call.id
                                json.field "type", call.type
                                if func = call.function
                                  json.field "function" do
                                    json.object do
                                      json.field "name", func.name
                                      json.field "arguments", func.arguments
                                    end
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                    if tcid = msg.tool_call_id
                      json.field "tool_call_id", tcid unless tcid.empty?
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
                      json.field "type", tool.type
                      json.field "function" do
                        json.object do
                          json.field "name", tool.function.name
                          json.field "description", tool.function.description
                          json.field "parameters" do
                            json.raw(tool.function.parameters.to_json)
                          end
                        end
                      end
                    end
                  end
                end
              end
            end

            # Apply options
            if opts = options
              if t = opts["temperature"]?
                json.field "temperature", t.as_f
              end
              if mt = opts["max_tokens"]?
                json.field "max_tokens", mt.as_i
              end
            end
          end
        end
        req
      end

      private def handle_response(response : HTTP::Client::Response, model : String) : LLMResponse
        unless response.success?
          reason = classify_error(response.status_code)
          raise FailoverError.new(reason, "openai_compat", model, response.status_code,
            Exception.new(response.body[0, 500]))
        end

        data = JSON.parse(response.body)
        choices = data["choices"]?
        unless choices && choices.as_a.size > 0
          return LLMResponse.new(content: "", finish_reason: "stop")
        end

        choice = choices.as_a[0]
        message = choice["message"]?
        finish_reason = choice["finish_reason"]?.try(&.as_s?) || "stop"

        content = message.try(&.["content"]?).try(&.as_s?) || ""

        tool_calls = [] of ToolCall
        if tcs = message.try(&.["tool_calls"]?)
          tcs.as_a.each do |tc|
            id = tc["id"]?.try(&.as_s?) || ""
            type = tc["type"]?.try(&.as_s?) || "function"
            func = tc["function"]?
            if func
              fname = func["name"]?.try(&.as_s?) || ""
              fargs = func["arguments"]?.try(&.as_s?) || "{}"
              tool_calls << ToolCall.new(
                id: id,
                type: type,
                function: FunctionCall.new(name: fname, arguments: fargs)
              )
            end
          end
        end

        usage_info = nil
        if u = data["usage"]?
          usage_info = UsageInfo.new(
            prompt_tokens: u["prompt_tokens"]?.try(&.as_i?) || 0,
            completion_tokens: u["completion_tokens"]?.try(&.as_i?) || 0,
            total_tokens: u["total_tokens"]?.try(&.as_i?) || 0,
          )
        end

        LLMResponse.new(
          content: content,
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
