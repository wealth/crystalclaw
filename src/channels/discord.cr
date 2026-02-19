require "http/client"
require "http/web_socket"
require "json"
require "./base"
require "../bus/bus"
require "../logger/logger"

module CrystalClaw
  module Channels
    class DiscordChannel < Channel
      @token : String
      @allow_from : Array(String)
      @bus : Bus::MessageBus
      @running : Bool
      @bot_id : String
      @heartbeat_interval : Int32
      @sequence : Int64?
      @session_id : String

      GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json"

      def initialize(@token, @allow_from, @bus)
        @running = false
        @bot_id = ""
        @heartbeat_interval = 41250
        @sequence = nil
        @session_id = ""
      end

      def name : String
        "discord"
      end

      def start : Nil
        @running = true
        spawn do
          connect_gateway
        end
      end

      def stop : Nil
        @running = false
      end

      private def connect_gateway
        while @running
          begin
            ws = HTTP::WebSocket.new(URI.parse(GATEWAY_URL), headers: HTTP::Headers{
              "Authorization" => "Bot #{@token}",
            })

            ws.on_message do |msg|
              handle_gateway_message(msg)
            end

            ws.on_close do |code, reason|
              Logger.warn("discord", "WebSocket closed: #{code} #{reason}")
            end

            # Send identify
            identify = {
              "op" => 2,
              "d"  => {
                "token"      => @token,
                "intents"    => 33281, # GUILDS | GUILD_MESSAGES | DIRECT_MESSAGES | MESSAGE_CONTENT
                "properties" => {
                  "os"      => "linux",
                  "browser" => "crystalclaw",
                  "device"  => "crystalclaw",
                },
              },
            }.to_json
            ws.send(identify)

            # Start heartbeat
            spawn do
              while @running
                sleep @heartbeat_interval.milliseconds
                heartbeat = {"op" => 1, "d" => @sequence}.to_json
                begin
                  ws.send(heartbeat)
                rescue
                  break
                end
              end
            end

            ws.run
          rescue ex
            Logger.error("discord", "Gateway error: #{ex.message}")
            sleep 5.seconds
          end
        end
      end

      private def handle_gateway_message(raw : String)
        data = JSON.parse(raw)
        op = data["op"]?.try(&.as_i?) || return

        case op
        when 0 # Dispatch
          @sequence = data["s"]?.try(&.as_i64?)
          event = data["t"]?.try(&.as_s?) || return
          handle_dispatch(event, data["d"]?)
        when 10 # Hello
          interval = data.dig?("d", "heartbeat_interval").try(&.as_i?)
          @heartbeat_interval = interval if interval
        when 11 # Heartbeat ACK
          # OK
        end
      end

      private def handle_dispatch(event : String, payload : JSON::Any?)
        return unless payload

        case event
        when "READY"
          @bot_id = payload.dig?("user", "id").try(&.as_s?) || ""
          @session_id = payload["session_id"]?.try(&.as_s?) || ""
          Logger.info("discord", "Bot ready as #{@bot_id}")
        when "MESSAGE_CREATE"
          handle_message(payload)
        end
      end

      private def handle_message(msg : JSON::Any)
        # Ignore own messages
        author_id = msg.dig?("author", "id").try(&.as_s?) || return
        return if author_id == @bot_id

        # Check if bot
        is_bot = msg.dig?("author", "bot").try(&.as_bool?) || false
        return if is_bot

        content = msg["content"]?.try(&.as_s?) || return
        channel_id = msg["channel_id"]?.try(&.as_s?) || return
        guild_id = msg["guild_id"]?.try(&.as_s?)

        # Allow list
        unless @allow_from.empty?
          unless @allow_from.includes?(author_id)
            return
          end
        end

        # In guilds, only respond when mentioned
        if guild_id
          unless content.includes?("<@#{@bot_id}>") || content.includes?("<@!#{@bot_id}>")
            return
          end
          content = content.gsub(/<@!?#{@bot_id}>/, "").strip
        end

        return if content.empty?

        Logger.info("discord", "Message from #{author_id} in #{channel_id}: #{content[0, 50]}")

        @bus.publish_inbound(Bus::InboundMessage.new(
          channel: "discord",
          sender_id: author_id,
          chat_id: channel_id,
          content: content,
          session_key: "discord:#{channel_id}",
          metadata: guild_id ? {"guild_id" => guild_id} : {} of String => String
        ))
      end

      def send_message(channel_id : String, text : String)
        url = "https://discord.com/api/v10/channels/#{channel_id}/messages"
        chunks = split_message(text, 2000) # Discord limit
        chunks.each do |chunk|
          body = {"content" => chunk}.to_json
          HTTP::Client.post(url,
            headers: HTTP::Headers{
              "Authorization" => "Bot #{@token}",
              "Content-Type"  => "application/json",
            },
            body: body
          )
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
