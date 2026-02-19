require "../bus/bus"

module CrystalClaw
  module Channels
    abstract class Channel
      abstract def name : String
      abstract def start : Nil
      abstract def stop : Nil

      def enabled? : Bool
        true
      end
    end

    class Manager
      @channels : Hash(String, Channel)
      @bus : Bus::MessageBus

      def initialize(@bus)
        @channels = {} of String => Channel
      end

      def register(channel : Channel)
        @channels[channel.name] = channel
      end

      def get_channel(name : String) : Channel?
        @channels[name]?
      end

      def get_enabled_channels : Array(String)
        @channels.select { |_, ch| ch.enabled? }.keys
      end

      def start_all
        @channels.each do |name, channel|
          next unless channel.enabled?
          begin
            channel.start
            Logger.info("channels", "Started channel: #{name}")
          rescue ex
            Logger.error("channels", "Failed to start channel #{name}: #{ex.message}")
          end
        end
      end

      def stop_all
        @channels.each do |name, channel|
          begin
            channel.stop
          rescue ex
            Logger.error("channels", "Error stopping channel #{name}: #{ex.message}")
          end
        end
      end
    end
  end
end
