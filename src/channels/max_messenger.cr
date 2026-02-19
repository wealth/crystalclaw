require "http/client"
require "json"
require "./base"
require "../bus/bus"
require "../logger/logger"

module CrystalClaw
  module Channels
    class MaxMessengerChannel < Channel
      API_BASE = "https://platform-api.max.ru"

      @token : String
      @allow_from : Array(String)
      @bus : Bus::MessageBus
      @running : Bool
      @marker : Int64?
      @bot_id : String

      def initialize(@token, @allow_from, @bus)
        @running = false
        @marker = nil
        @bot_id = ""
      end

      def name : String
        "max_messenger"
      end

      def start : Nil
        @running = true
        spawn do
          fetch_bot_info
          poll_loop
        end
      end

      def stop : Nil
        @running = false
      end

      private def auth_headers : HTTP::Headers
        HTTP::Headers{
          "Authorization" => "access_token=#{@token}",
          "Content-Type"  => "application/json",
        }
      end

      private def fetch_bot_info
        url = "#{API_BASE}/me"
        begin
          response = HTTP::Client.get(url, headers: auth_headers)
          if response.success?
            data = JSON.parse(response.body)
            @bot_id = data["user_id"]?.try(&.as_i64?).try(&.to_s) || ""
            bot_name = data["name"]?.try(&.as_s?) || "unknown"
            Logger.info("max_messenger", "Bot ready: #{bot_name} (#{@bot_id})")
          else
            Logger.error("max_messenger", "Failed to fetch bot info: HTTP #{response.status_code}")
          end
        rescue ex
          Logger.error("max_messenger", "Error fetching bot info: #{ex.message}")
        end
      end

      private def poll_loop
        while @running
          begin
            updates = get_updates
            updates.each do |update|
              process_update(update)
            end
          rescue ex
            Logger.error("max_messenger", "Poll error: #{ex.message}")
            sleep 5.seconds
          end
          sleep 0.5.seconds
        end
      end

      private def get_updates : Array(JSON::Any)
        url = String.build do |s|
          s << API_BASE << "/updates?timeout=30"
          if m = @marker
            s << "&marker=" << m
          end
          s << "&types=message_created"
        end

        response = HTTP::Client.get(url, headers: auth_headers)
        return [] of JSON::Any unless response.success?

        data = JSON.parse(response.body)

        # Update marker for next poll
        if new_marker = data["marker"]?.try(&.as_i64?)
          @marker = new_marker
        end

        data["updates"]?.try(&.as_a?) || [] of JSON::Any
      end

      private def process_update(update : JSON::Any)
        update_type = update["update_type"]?.try(&.as_s?) || return
        return unless update_type == "message_created"

        message = update["message"]? || return
        body = message["body"]? || return
        text = body["text"]?.try(&.as_s?) || return

        sender = message["sender"]? || return
        sender_id = sender["user_id"]?.try(&.as_i64?).try(&.to_s) || return

        chat_id = message.dig?("recipient", "chat_id").try(&.as_i64?).try(&.to_s) || return

        # Ignore own messages
        return if sender_id == @bot_id

        # Check allow list
        unless @allow_from.empty?
          unless @allow_from.includes?(sender_id)
            return
          end
        end

        return if text.empty?

        Logger.info("max_messenger", "Message from #{sender_id} in #{chat_id}: #{text[0, 50]}")

        @bus.publish_inbound(Bus::InboundMessage.new(
          channel: "max_messenger",
          sender_id: sender_id,
          chat_id: chat_id,
          content: text,
          session_key: "max_messenger:#{chat_id}"
        ))
      end

      def send_message(chat_id : String, text : String)
        chunks = split_message(text, 4000) # Max Messenger limit
        chunks.each do |chunk|
          url = "#{API_BASE}/messages?chat_id=#{chat_id}"
          body = {"text" => chunk}.to_json

          begin
            HTTP::Client.post(url,
              headers: auth_headers,
              body: body
            )
          rescue ex
            Logger.error("max_messenger", "Send error: #{ex.message}")
          end
        end
      end

      private def split_message(text : String, max_length : Int32) : Array(String)
        return [text] if text.size <= max_length
        chunks = [] of String
        while text.size > max_length
          split_pos = text.rindex('\n', max_length) || max_length
          chunks << text[0, split_pos]
          text = text[split_pos..].lstrip
        end
        chunks << text unless text.empty?
        chunks
      end
    end
  end
end
