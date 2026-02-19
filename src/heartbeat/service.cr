require "json"
require "../logger/logger"

module CrystalClaw
  module Heartbeat
    class Service
      @workspace : String
      @interval : Int32
      @enabled : Bool
      @running : Bool
      @handler : Proc(String, String, String, Nil)?

      def initialize(@workspace, @interval = 30, @enabled = false)
        @running = false
        @handler = nil
      end

      def set_handler(&block : String, String, String -> Nil)
        @handler = block
      end

      def start
        return unless @enabled
        @running = true
        spawn do
          heartbeat_loop
        end
      end

      def stop
        @running = false
      end

      private def heartbeat_loop
        while @running
          sleep @interval.minutes
          next unless @running

          begin
            prompt = load_heartbeat_prompt
            next if prompt.empty?

            Logger.info("heartbeat", "Running heartbeat tasks")
            handler = @handler
            handler.try(&.call(prompt, "", ""))
          rescue ex
            Logger.error("heartbeat", "Heartbeat error: #{ex.message}")
          end
        end
      end

      private def load_heartbeat_prompt : String
        path = File.join(@workspace, "HEARTBEAT.md")
        if File.exists?(path)
          File.read(path).strip
        else
          ""
        end
      end
    end
  end
end
