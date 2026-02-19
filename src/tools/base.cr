require "json"
require "../providers/types"

module CrystalClaw
  module Tools
    # ── Tool result ──

    struct ToolResult
      property content : String
      property error : Bool
      property silent : Bool

      def initialize(@content = "", @error = false, @silent = false)
      end

      def self.success(content : String) : ToolResult
        ToolResult.new(content: content)
      end

      def self.error(content : String) : ToolResult
        ToolResult.new(content: content, error: true)
      end

      def self.silent(content : String) : ToolResult
        ToolResult.new(content: content, silent: true)
      end
    end

    # ── Tool interface ──

    abstract class Tool
      abstract def name : String
      abstract def description : String
      abstract def parameters : Hash(String, JSON::Any)
      abstract def execute(args : Hash(String, JSON::Any)) : ToolResult

      def to_definition : Providers::ToolDefinition
        func = Providers::ToolFunctionDefinition.new(
          name: name,
          description: description,
          parameters: parameters
        )
        Providers::ToolDefinition.new(type: "function", function: func)
      end
    end

    # Tool that has awareness of current channel context
    module ContextualTool
      property context_channel : String = ""
      property context_chat_id : String = ""

      def set_context(channel : String, chat_id : String)
        @context_channel = channel
        @context_chat_id = chat_id
      end
    end

    # ── Tool registry ──

    class ToolRegistry
      @tools : Hash(String, Tool)

      def initialize
        @tools = {} of String => Tool
      end

      def register(tool : Tool)
        @tools[tool.name] = tool
      end

      def get(name : String) : Tool?
        @tools[name]?
      end

      def list : Array(Tool)
        @tools.values
      end

      def names : Array(String)
        @tools.keys
      end

      def size : Int32
        @tools.size
      end

      def to_definitions : Array(Providers::ToolDefinition)
        @tools.values.map(&.to_definition)
      end

      def has?(name : String) : Bool
        @tools.has_key?(name)
      end
    end
  end
end
