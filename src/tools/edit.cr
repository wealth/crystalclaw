require "json"
require "./base"

module CrystalClaw
  module Tools
    class EditFileTool < Tool
      @workspace : String
      @restrict : Bool

      def initialize(@workspace, @restrict = true)
      end

      def name : String
        "edit_file"
      end

      def description : String
        "Edit a file by replacing old_text with new_text. The old_text must match exactly."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"path":{"type":"string","description":"Absolute path to the file to edit"},"old_text":{"type":"string","description":"The exact text to find and replace"},"new_text":{"type":"string","description":"The replacement text"}},"required":["path","old_text","new_text"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        path = args["path"]?.try(&.as_s?) || return ToolResult.error("Missing 'path' argument")
        old_text = args["old_text"]?.try(&.as_s?) || return ToolResult.error("Missing 'old_text' argument")
        new_text = args["new_text"]?.try(&.as_s?) || return ToolResult.error("Missing 'new_text' argument")

        if @restrict && !within_workspace?(path)
          return ToolResult.error("Path outside working directory: #{path}")
        end

        unless File.exists?(path)
          return ToolResult.error("File not found: #{path}")
        end

        begin
          content = File.read(path)
          count = content.scan(old_text).size

          if count == 0
            return ToolResult.error("old_text not found in file")
          elsif count > 1
            return ToolResult.error("old_text found #{count} times, must be unique. Provide more context.")
          end

          new_content = content.sub(old_text, new_text)
          File.write(path, new_content)
          ToolResult.success("Successfully edited #{path}")
        rescue ex
          ToolResult.error("Error editing file: #{ex.message}")
        end
      end

      private def within_workspace?(path : String) : Bool
        abs = File.expand_path(path)
        ws = File.expand_path(@workspace)
        abs.starts_with?(ws)
      end
    end
  end
end
