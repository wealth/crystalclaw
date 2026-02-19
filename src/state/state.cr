require "json"

module CrystalClaw
  module State
    class Manager
      @state_dir : String
      @state_file : String

      def initialize(workspace : String)
        @state_dir = File.join(workspace, "state")
        @state_file = File.join(@state_dir, "state.json")
        Dir.mkdir_p(@state_dir)
      end

      def set_last_channel(channel : String)
        data = load_state
        data["last_channel"] = JSON::Any.new(channel)
        save_state(data)
      end

      def get_last_channel : String?
        load_state["last_channel"]?.try(&.as_s?)
      end

      def set_last_chat_id(chat_id : String)
        data = load_state
        data["last_chat_id"] = JSON::Any.new(chat_id)
        save_state(data)
      end

      def get_last_chat_id : String?
        load_state["last_chat_id"]?.try(&.as_s?)
      end

      def set(key : String, value : String)
        data = load_state
        data[key] = JSON::Any.new(value)
        save_state(data)
      end

      def get(key : String) : String?
        load_state[key]?.try(&.as_s?)
      end

      private def load_state : Hash(String, JSON::Any)
        if File.exists?(@state_file)
          begin
            JSON.parse(File.read(@state_file)).as_h
          rescue
            {} of String => JSON::Any
          end
        else
          {} of String => JSON::Any
        end
      end

      private def save_state(data : Hash(String, JSON::Any))
        File.write(@state_file, data.to_pretty_json)
      end
    end
  end
end
