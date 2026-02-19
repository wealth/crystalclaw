require "json"
require "./base"

module CrystalClaw
  module Tools
    class ShellTool < Tool
      @workspace : String
      @restrict : Bool
      @timeout : Time::Span

      # Dangerous patterns that are always blocked
      DANGEROUS_PATTERNS = [
        "rm -rf /",
        "rm -rf /*",
        "mkfs",
        "format",
        "diskpart",
        "dd if=",
        "/dev/sd",
        "shutdown",
        "reboot",
        "poweroff",
        ":(){ :|:& };:",
        "del /f",
        "rmdir /s",
      ]

      def initialize(@workspace, @restrict = true, @timeout = 30.seconds)
      end

      def name : String
        "exec"
      end

      def description : String
        "Execute a shell command and return its output. Use this for running programs, scripts, or system commands."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"command":{"type":"string","description":"The shell command to execute"},"working_dir":{"type":"string","description":"Working directory for the command (optional)"}},"required":["command"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        command = args["command"]?.try(&.as_s?) || return ToolResult.error("Missing 'command' argument")
        working_dir = args["working_dir"]?.try(&.as_s?)

        # Safety check
        DANGEROUS_PATTERNS.each do |pattern|
          if command.includes?(pattern)
            return ToolResult.error("Command blocked by safety guard (dangerous pattern detected): #{pattern}")
          end
        end

        # Workspace restriction check
        if @restrict && working_dir
          abs = File.expand_path(working_dir)
          ws = File.expand_path(@workspace)
          unless abs.starts_with?(ws)
            return ToolResult.error("Command blocked by safety guard (path outside working dir)")
          end
        end

        dir = working_dir || @workspace

        begin
          output = IO::Memory.new
          error = IO::Memory.new
          status = Process.run(
            "sh", ["-c", command],
            output: output,
            error: error,
            chdir: File.directory?(dir) ? dir : nil
          )

          stdout = output.to_s
          stderr = error.to_s
          result_text = String.build do |str|
            str << "Exit code: #{status.exit_code}\n"
            unless stdout.empty?
              if stdout.bytesize > 50_000
                stdout = stdout[0, 50_000] + "\n... (output truncated)"
              end
              str << "stdout:\n#{stdout}\n"
            end
            unless stderr.empty?
              if stderr.bytesize > 10_000
                stderr = stderr[0, 10_000] + "\n... (stderr truncated)"
              end
              str << "stderr:\n#{stderr}"
            end
          end

          if status.success?
            ToolResult.success(result_text)
          else
            ToolResult.error(result_text)
          end
        rescue ex
          ToolResult.error("Error executing command: #{ex.message}")
        end
      end
    end
  end
end
