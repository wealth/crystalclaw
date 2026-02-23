require "json"

module CrystalClaw
  module State
    class Manager
      STATE_KEY = "_state"
      @store : Memory::Store

      def initialize(@store)
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
        raw = @store.get(STATE_KEY)
        return {} of String => JSON::Any if raw.empty?
        begin
          JSON.parse(raw).as_h
        rescue
          {} of String => JSON::Any
        end
      end

      private def save_state(data : Hash(String, JSON::Any))
        @store.set(STATE_KEY, data.to_pretty_json)
      end
    end
  end
end
