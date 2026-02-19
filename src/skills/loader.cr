module CrystalClaw
  module Skills
    struct SkillInfo
      property name : String
      property description : String
      property source : String
      property path : String

      def initialize(@name, @description = "", @source = "local", @path = "")
      end
    end

    class Loader
      @workspace_skills_dir : String
      @global_skills_dir : String
      @builtin_skills_dir : String

      def initialize(workspace : String, @global_skills_dir = "", @builtin_skills_dir = "")
        @workspace_skills_dir = File.join(workspace, "skills")
      end

      def list_skills : Array(SkillInfo)
        skills = [] of SkillInfo

        # Workspace skills
        scan_dir(@workspace_skills_dir, "workspace").each { |s| skills << s }

        # Global skills
        unless @global_skills_dir.empty?
          scan_dir(@global_skills_dir, "global").each { |s| skills << s }
        end

        # Builtin skills
        unless @builtin_skills_dir.empty?
          scan_dir(@builtin_skills_dir, "builtin").each { |s| skills << s }
        end

        skills
      end

      def load_skill(name : String) : String?
        # Search in workspace first, then global, then builtin
        [@workspace_skills_dir, @global_skills_dir, @builtin_skills_dir].each do |dir|
          next if dir.empty?
          skill_file = File.join(dir, name, "SKILL.md")
          if File.exists?(skill_file)
            return File.read(skill_file)
          end
        end
        nil
      end

      def available_count : Int32
        list_skills.size
      end

      private def scan_dir(dir : String, source : String) : Array(SkillInfo)
        skills = [] of SkillInfo
        return skills unless Dir.exists?(dir)

        Dir.each_child(dir) do |child|
          child_path = File.join(dir, child)
          next unless File.directory?(child_path)

          skill_file = File.join(child_path, "SKILL.md")
          next unless File.exists?(skill_file)

          description = extract_description(skill_file)
          skills << SkillInfo.new(
            name: child,
            description: description,
            source: source,
            path: child_path
          )
        end

        skills
      end

      private def extract_description(path : String) : String
        content = File.read(path)
        # Try to extract description from YAML frontmatter
        if content.starts_with?("---")
          if end_idx = content.index("---", 3)
            frontmatter = content[3, end_idx - 3]
            frontmatter.each_line do |line|
              if line.starts_with?("description:")
                return line.sub("description:", "").strip.strip('"')
              end
            end
          end
        end
        # Fallback: first non-empty line
        content.each_line do |line|
          line = line.strip
          next if line.empty? || line.starts_with?("#") || line.starts_with?("---")
          return line[0, 100]
        end
        ""
      end
    end
  end
end
