require "./instance"
require "../config/config"
require "../providers/types"
require "../memory/factory"

module CrystalClaw
  module Agent
    class Registry
      @agents : Hash(String, Instance)
      @default_id : String

      def initialize(cfg : Config)
        @agents = {} of String => Instance
        @default_id = "default"

        # Create memory store from config
        memory_store = Memory.create_store(cfg)

        # Create default agent from config defaults
        defaults = cfg.agents.defaults
        default_agent = Instance.new(
          id: "default",
          name: "CrystalClaw",
          workspace: defaults.workspace,
          model: defaults.model,
          model_fallbacks: defaults.model_fallbacks,
          max_tokens: defaults.max_tokens,
          temperature: defaults.temperature,
          max_tool_iterations: defaults.max_tool_iterations,
          restrict_to_workspace: defaults.restrict_to_workspace,
          report_tool_usage: defaults.report_tool_usage,
          memory_store: memory_store
        )
        default_agent.register_default_tools
        @agents["default"] = default_agent

        # Create additional agents from config list
        cfg.agents.list.each do |agent_cfg|
          id = agent_cfg.id
          next if id.empty?

          ws = agent_cfg.workspace.empty? ? defaults.workspace : agent_cfg.workspace
          model = agent_cfg.model.empty? ? defaults.model : agent_cfg.model

          agent = Instance.new(
            id: id,
            name: agent_cfg.name.empty? ? id : agent_cfg.name,
            workspace: ws,
            model: model,
            max_tokens: defaults.max_tokens,
            temperature: defaults.temperature,
            max_tool_iterations: defaults.max_tool_iterations,
            restrict_to_workspace: defaults.restrict_to_workspace,
            report_tool_usage: defaults.report_tool_usage,
            memory_store: memory_store
          )
          agent.register_default_tools
          @agents[id] = agent

          if agent_cfg.default
            @default_id = id
          end
        end
      end

      def get_agent(id : String) : Instance?
        @agents[id]?
      end

      def get_default_agent : Instance
        @agents[@default_id]? || @agents.values.first
      end

      def list_agent_ids : Array(String)
        @agents.keys
      end

      def register_tool_to_all(tool : Tools::Tool)
        @agents.each_value do |agent|
          agent.tools.register(tool)
        end
      end
    end
  end
end
