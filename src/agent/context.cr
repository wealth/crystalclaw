module CrystalClaw
  module Agent
    class ContextBuilder
      @workspace : String
      @tools_registry : Tools::ToolRegistry?

      def initialize(@workspace)
      end

      def set_tools_registry(registry : Tools::ToolRegistry)
        @tools_registry = registry
      end

      def build_system_prompt : String
        parts = [] of String

        # Load identity
        identity = load_file("IDENTITY.md")
        parts << identity unless identity.empty?

        # Load soul
        soul = load_file("SOUL.md")
        parts << soul unless soul.empty?

        # Load agent behavior
        agent_md = load_file("AGENT.md")
        parts << agent_md unless agent_md.empty?

        # Load user preferences
        user = load_file("USER.md")
        parts << "## User Preferences\n#{user}" unless user.empty?

        # Load tools descriptions
        tools_md = load_file("TOOLS.md")
        parts << tools_md unless tools_md.empty?

        # Load memory
        memory = load_file("memory/MEMORY.md")
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

      private def load_file(relative_path : String) : String
        path = File.join(@workspace, relative_path)
        if File.exists?(path)
          File.read(path).strip
        else
          ""
        end
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
