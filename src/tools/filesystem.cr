require "json"
require "./base"

module CrystalClaw
  module Tools
    # ── Filesystem Tools ──

    class ReadFileTool < Tool
      @workspace : String
      @restrict : Bool

      def initialize(@workspace, @restrict = true)
      end

      def name : String
        "read_file"
      end

      def description : String
        "Read the contents of a file at the given path. Use this when you need to examine existing file contents."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the file to read"}},"required":["path"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        path = args["path"]?.try(&.as_s?) || return ToolResult.error("Missing 'path' argument")

        if @restrict && !within_workspace?(path)
          return ToolResult.error("Path outside working directory: #{path}")
        end

        unless File.exists?(path)
          return ToolResult.error("File not found: #{path}")
        end

        begin
          content = File.read(path)
          if content.bytesize > 100_000
            content = content[0, 100_000] + "\n... (truncated, file too large)"
          end
          ToolResult.success(content)
        rescue ex
          ToolResult.error("Error reading file: #{ex.message}")
        end
      end

      private def within_workspace?(path : String) : Bool
        abs = File.expand_path(path)
        ws = File.expand_path(@workspace)
        abs.starts_with?(ws)
      end
    end

    class WriteFileTool < Tool
      @workspace : String
      @restrict : Bool

      def initialize(@workspace, @restrict = true)
      end

      def name : String
        "write_file"
      end

      def description : String
        "Write content to a file at the given path. Creates parent directories if needed. Overwrites existing content."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"path":{"type":"string","description":"Absolute path to write to"},"content":{"type":"string","description":"Content to write"}},"required":["path","content"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        path = args["path"]?.try(&.as_s?) || return ToolResult.error("Missing 'path' argument")
        content = args["content"]?.try(&.as_s?) || return ToolResult.error("Missing 'content' argument")

        if @restrict && !within_workspace?(path)
          return ToolResult.error("Path outside working directory: #{path}")
        end

        begin
          Dir.mkdir_p(File.dirname(path))
          File.write(path, content)
          ToolResult.success("Successfully wrote #{content.bytesize} bytes to #{path}")
        rescue ex
          ToolResult.error("Error writing file: #{ex.message}")
        end
      end

      private def within_workspace?(path : String) : Bool
        abs = File.expand_path(path)
        ws = File.expand_path(@workspace)
        abs.starts_with?(ws)
      end
    end

    class AppendFileTool < Tool
      @workspace : String
      @restrict : Bool

      def initialize(@workspace, @restrict = true)
      end

      def name : String
        "append_file"
      end

      def description : String
        "Append content to the end of a file. Creates the file if it doesn't exist."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"path":{"type":"string","description":"Absolute path to append to"},"content":{"type":"string","description":"Content to append"}},"required":["path","content"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        path = args["path"]?.try(&.as_s?) || return ToolResult.error("Missing 'path' argument")
        content = args["content"]?.try(&.as_s?) || return ToolResult.error("Missing 'content' argument")

        if @restrict && !within_workspace?(path)
          return ToolResult.error("Path outside working directory: #{path}")
        end

        begin
          Dir.mkdir_p(File.dirname(path))
          File.open(path, "a") { |f| f.print(content) }
          ToolResult.success("Successfully appended #{content.bytesize} bytes to #{path}")
        rescue ex
          ToolResult.error("Error appending to file: #{ex.message}")
        end
      end

      private def within_workspace?(path : String) : Bool
        abs = File.expand_path(path)
        ws = File.expand_path(@workspace)
        abs.starts_with?(ws)
      end
    end

    class ListDirTool < Tool
      @workspace : String
      @restrict : Bool

      def initialize(@workspace, @restrict = true)
      end

      def name : String
        "list_dir"
      end

      def description : String
        "List files and directories at the given path."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the directory to list"}},"required":["path"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        path = args["path"]?.try(&.as_s?) || return ToolResult.error("Missing 'path' argument")

        if @restrict && !within_workspace?(path)
          return ToolResult.error("Path outside working directory: #{path}")
        end

        unless Dir.exists?(path)
          return ToolResult.error("Directory not found: #{path}")
        end

        begin
          entries = [] of String
          Dir.each_child(path) do |child|
            full = File.join(path, child)
            if File.directory?(full)
              entries << "#{child}/"
            else
              size = File.size(full)
              entries << "#{child} (#{format_size(size)})"
            end
          end

          if entries.empty?
            ToolResult.success("Directory is empty: #{path}")
          else
            ToolResult.success(entries.join("\n"))
          end
        rescue ex
          ToolResult.error("Error listing directory: #{ex.message}")
        end
      end

      private def within_workspace?(path : String) : Bool
        abs = File.expand_path(path)
        ws = File.expand_path(@workspace)
        abs.starts_with?(ws)
      end

      private def format_size(bytes) : String
        if bytes < 1024
          "#{bytes}B"
        elsif bytes < 1024 * 1024
          "#{(bytes / 1024.0).round(1)}KB"
        else
          "#{(bytes / (1024.0 * 1024.0)).round(1)}MB"
        end
      end
    end
  end
end
