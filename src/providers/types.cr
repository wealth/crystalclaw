require "json"

module CrystalClaw
  module Providers
    # ── Core message types ──

    class Message
      include JSON::Serializable

      property role : String
      property content : String?
      property tool_calls : Array(ToolCall)?
      property tool_call_id : String?

      def initialize(@role, @content = nil, @tool_calls = nil, @tool_call_id = nil)
      end
    end

    class ToolCall
      include JSON::Serializable

      property id : String
      property type : String
      property function : FunctionCall?

      def initialize(@id, @type = "function", @function = nil)
      end
    end

    class FunctionCall
      include JSON::Serializable

      property name : String
      property arguments : String # raw JSON string

      def initialize(@name, @arguments = "{}")
      end
    end

    class LLMResponse
      include JSON::Serializable

      property content : String
      property tool_calls : Array(ToolCall)
      property finish_reason : String
      property usage : UsageInfo?

      def initialize(@content = "", @tool_calls = [] of ToolCall, @finish_reason = "stop", @usage = nil)
      end
    end

    class UsageInfo
      include JSON::Serializable

      property prompt_tokens : Int32
      property completion_tokens : Int32
      property total_tokens : Int32

      def initialize(@prompt_tokens = 0, @completion_tokens = 0, @total_tokens = 0)
      end
    end

    # ── Tool definition types (sent to LLM) ──

    class ToolDefinition
      include JSON::Serializable

      property type : String
      property function : ToolFunctionDefinition

      def initialize(@type = "function", @function = ToolFunctionDefinition.new)
      end
    end

    class ToolFunctionDefinition
      include JSON::Serializable

      property name : String
      property description : String
      property parameters : Hash(String, JSON::Any)

      def initialize(@name = "", @description = "", @parameters = {} of String => JSON::Any)
      end
    end

    # ── Provider interface ──

    abstract class LLMProvider
      abstract def chat(messages : Array(Message), tools : Array(ToolDefinition), model : String, options : Hash(String, JSON::Any)?) : LLMResponse
      abstract def default_model : String
    end

    # ── Failover types ──

    enum FailoverReason
      Auth
      RateLimit
      Billing
      Timeout
      Format
      Overloaded
      Unknown
    end

    class FailoverError < Exception
      property reason : FailoverReason
      property provider : String
      property model : String
      property status : Int32
      property wrapped : Exception?

      def initialize(@reason, @provider, @model, @status = 0, @wrapped = nil)
        super("failover(#{@reason}): provider=#{@provider} model=#{@model} status=#{@status}: #{@wrapped.try(&.message)}")
      end

      def retriable? : Bool
        reason != FailoverReason::Format
      end
    end
  end
end
