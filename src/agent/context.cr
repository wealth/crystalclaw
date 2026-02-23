require "../memory/base"

module CrystalClaw
  module Agent
    class ContextBuilder
      @workspace : String
      @tools_registry : Tools::ToolRegistry?
      @memory_store : Memory::Store

      def initialize(@workspace, @memory_store)
      end

      def set_tools_registry(registry : Tools::ToolRegistry)
        @tools_registry = registry
      end

      def build_system_prompt : String
        parts = [] of String

        # Load identity
        identity = @memory_store.get("IDENTITY.md")
        parts << identity unless identity.empty?

        # Load soul
        soul = @memory_store.get("SOUL.md")
        parts << soul unless soul.empty?

        # Load agent behavior
        agent_md = @memory_store.get("AGENT.md")
        parts << agent_md unless agent_md.empty?

        # Load user preferences
        user = @memory_store.get("USER.md")
        parts << "## User Preferences\n#{user}" unless user.empty?

        # Load tools descriptions
        tools_md = @memory_store.get("TOOLS.md")
        parts << tools_md unless tools_md.empty?

        # Load memory from configured store
        memory = @memory_store.load
        parts << "## Memory\n#{memory}" unless memory.empty?

        # Load skills
        skills_prompt = load_skills_prompt
        parts << skills_prompt unless skills_prompt.empty?

        # Add available tools list
        if registry = @tools_registry
          tool_names = registry.names
          unless tool_names.empty?
            parts << "## Available Tools\nYou have access to the following tools: #{tool_names.join(", ")}"
          end
        end

        # Add timing info
        parts << "Current time: #{Time.local.to_s("%Y-%m-%d %H:%M:%S %z")}"

        parts.join("\n\n")
      end

      private def load_skills_prompt : String
        skills_dir = File.join(@workspace, "skills")
        return "" unless Dir.exists?(skills_dir)

        skills = [] of String
        Dir.each_child(skills_dir) do |child|
          skill_file = File.join(skills_dir, child, "SKILL.md")
          if File.exists?(skill_file)
            content = File.read(skill_file).strip
            skills << "### Skill: #{child}\n#{content}" unless content.empty?
          end
        end

        return "" if skills.empty?
        "## Skills\n#{skills.join("\n\n")}"
      end
    end
  end
end
