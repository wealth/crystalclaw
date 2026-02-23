require "json"
require "db"
require "./base"
require "../config/config"

module CrystalClaw
  module Tools
    # ── Config Management Tools ──

    class UpdateConfigTool < Tool
      @db : DB::Database

      def initialize(@db)
      end

      def name : String
        "update_config"
      end

      def description : String
        "Update a configuration key in the database. Uses dot-notation paths (e.g. 'channels.telegram.token', 'providers.openrouter.api_key', 'heartbeat.enabled'). The value is parsed as JSON if valid, otherwise treated as a string."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({
          "type": "object",
          "properties": {
            "key": {
              "type": "string",
              "description": "Dot-notation path to the config key (e.g. 'channels.telegram.token', 'providers.openrouter.api_key', 'heartbeat.enabled')"
            },
            "value": {
              "type": "string",
              "description": "New value for the key. Will be parsed as JSON if valid (for booleans, numbers, arrays), otherwise treated as a string."
            }
          },
          "required": ["key", "value"]
        })).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        key = args["key"]?.try(&.as_s?) || return ToolResult.error("Missing 'key' argument")
        value_str = args["value"]?.try(&.as_s?) || return ToolResult.error("Missing 'value' argument")

        # Load current config JSON from DB
        data = @db.query_one?(
          "SELECT content FROM workspace_data WHERE key = $1",
          Config::CONFIG_PG_KEY,
          as: String
        )

        config_json = if data && !data.empty?
                        JSON.parse(data)
                      else
                        # Start from default config
                        JSON.parse(Config.default.to_json)
                      end

        # Parse the value
        parsed_value = begin
          JSON.parse(value_str)
        rescue
          JSON::Any.new(value_str)
        end

        # Navigate the dot path and set the value
        parts = key.split(".")
        if parts.empty?
          return ToolResult.error("Invalid key: empty path")
        end

        begin
          set_nested_value(config_json, parts, parsed_value)
        rescue ex
          return ToolResult.error("Failed to set config key '#{key}': #{ex.message}")
        end

        # Save back to DB
        @db.exec(
          <<-SQL,
          INSERT INTO workspace_data (key, content, updated_at)
          VALUES ($1, $2, NOW())
          ON CONFLICT (key) DO UPDATE SET content = $2, updated_at = NOW()
          SQL
          Config::CONFIG_PG_KEY, config_json.to_pretty_json
        )

        ToolResult.success("Successfully updated config key '#{key}' to: #{parsed_value.to_json}. Use the reinitialize tool to apply changes.")
      end

      private def set_nested_value(root : JSON::Any, parts : Array(String), value : JSON::Any)
        current = root.as_h? || raise "Config root is not an object"

        # Navigate to the parent of the target key
        parts[0..-2].each_with_index do |part, i|
          child = current[part]?
          unless child
            raise "Key path segment '#{parts[0..i].join(".")}' not found in config"
          end
          current = child.as_h? || raise "Key path segment '#{parts[0..i].join(".")}' is not an object"
        end

        # Set the final key
        last_key = parts.last
        unless current.has_key?(last_key)
          raise "Key '#{key_path(parts)}' not found in config. Available keys at '#{key_path(parts[0..-2])}': #{current.keys.join(", ")}"
        end
        current[last_key] = value
      end

      private def key_path(parts : Array(String)) : String
        parts.join(".")
      end
    end

    class ReinitializeTool < Tool
      @reinit_callback : Proc(String)

      def initialize(&@reinit_callback : -> String)
      end

      def name : String
        "reinitialize"
      end

      def description : String
        "Reinitialize the agent by reloading configuration from the database. Use this after updating config keys to apply changes. The agent will reload its config, rebuild its tool registry, and report the new state."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({ "type": "object", "properties": {}, "required": [] })).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        begin
          result = @reinit_callback.call
          ToolResult.success(result)
        rescue ex
          ToolResult.error("Reinitialization failed: #{ex.message}")
        end
      end
    end
  end
end
