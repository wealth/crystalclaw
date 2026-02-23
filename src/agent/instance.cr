require "./context"
require "../tools/base"
require "../session/manager"
require "../memory/base"

module CrystalClaw
  module Agent
    class Instance
      property id : String
      property name : String
      property workspace : String
      property model : String
      property model_fallbacks : Array(String)
      property max_tokens : Int32
      property temperature : Float64
      property max_tool_iterations : Int32
      property restrict_to_workspace : Bool
      property tools : Tools::ToolRegistry
      property context_builder : ContextBuilder
      property session_manager : Session::Manager
      property memory_store : Memory::Store

      def initialize(
        @id = "default",
        @name = "CrystalClaw",
        @workspace = "",
        @model = "",
        @model_fallbacks = [] of String,
        @max_tokens = 8192,
        @temperature = 0.7,
        @max_tool_iterations = 20,
        @restrict_to_workspace = true,
        memory_store : Memory::Store? = nil,
      )
        ws = @workspace.sub("~", Path.home.to_s)
        @workspace = ws
        @tools = Tools::ToolRegistry.new
        @memory_store = memory_store || Memory::FileStore.new(ws)
        @context_builder = ContextBuilder.new(ws, @memory_store)
        @session_manager = Session::Manager.new(@memory_store)
      end

      def register_default_tools
        @tools.register(Tools::ReadFileTool.new(@workspace, @restrict_to_workspace))
        @tools.register(Tools::WriteFileTool.new(@workspace, @restrict_to_workspace))
        @tools.register(Tools::AppendFileTool.new(@workspace, @restrict_to_workspace))
        @tools.register(Tools::ListDirTool.new(@workspace, @restrict_to_workspace))
        @tools.register(Tools::EditFileTool.new(@workspace, @restrict_to_workspace))
        @tools.register(Tools::ShellTool.new(@workspace, @restrict_to_workspace))

        # Set tools registry in context builder
        @context_builder.set_tools_registry(@tools)
      end
    end
  end
end
