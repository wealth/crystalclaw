require "json"

module CrystalClaw
  module State
    class Manager
      STATE_KEY = "_state"
      @store : Memory::Store

      def initialize(@store)
      end

      def set_last_channel(channel : String)
        set("last_channel", channel)
      end

      def get_last_channel : String?
        get("last_channel")
      end

      def set_last_chat_id(chat_id : String)
        set("last_chat_id", chat_id)
      end

      def get_last_chat_id : String?
        get("last_chat_id")
      end

      def set(key : String, value : String)
        @store.set_state(key, value)
      end

      def get(key : String) : String?
        val = @store.get_state(key)
        val.empty? ? nil : val
      end
    end
  end
end
