require "http/client"
require "json"
require "./base"
require "../bus/bus"
require "../logger/logger"

module CrystalClaw
  module Channels
    class TelegramChannel < Channel
      @token : String
      @allow_from : Array(String)
      @bus : Bus::MessageBus
      @running : Bool
      @offset : Int64

      def initialize(@token, @allow_from, @bus)
        @running = false
        @offset = 0_i64
      end

      def name : String
        "telegram"
      end

      def start : Nil
        @running = true
        spawn do
          poll_loop
        end
      end

      def stop : Nil
        @running = false
      end

      private def poll_loop
        while @running
          begin
            updates = get_updates
            updates.each do |update|
              process_update(update)
            end
          rescue ex
            Logger.error("telegram", "Poll error: #{ex.message}")
            sleep 5.seconds
          end
          sleep 1.seconds
        end
      end

      private def get_updates : Array(JSON::Any)
        url = "https://api.telegram.org/bot#{@token}/getUpdates?offset=#{@offset}&timeout=30"
        response = HTTP::Client.get(url)
        return [] of JSON::Any unless response.success?

        data = JSON.parse(response.body)
        result = data["result"]?.try(&.as_a?) || [] of JSON::Any
        result
      end

      private def process_update(update : JSON::Any)
        update_id = update["update_id"]?.try(&.as_i64?) || return
        @offset = update_id + 1

        message = update["message"]?
        return unless message

        chat_id = message.dig?("chat", "id").try(&.as_i64?).try(&.to_s) || return
        sender_id = message.dig?("from", "id").try(&.as_i64?).try(&.to_s) || ""
        text = message["text"]?.try(&.as_s?) || return

        # Check allow list
        unless @allow_from.empty?
          unless @allow_from.includes?(sender_id) || @allow_from.includes?(chat_id)
            return
          end
        end

        # For group chats, only respond when @mentioned
        chat_type = message.dig?("chat", "type").try(&.as_s?) || "private"
        if chat_type == "group" || chat_type == "supergroup"
          bot_username = get_bot_username
          unless text.includes?("@#{bot_username}") || text.starts_with?("/")
            return
          end
          text = text.gsub("@#{bot_username}", "").strip
        end

        return if text.empty?

        Logger.info("telegram", "Message from #{sender_id} in #{chat_id}: #{text[0, 50]}")

        # Send "Thinking..." placeholder immediately
        metadata = {} of String => String
        if thinking_id = send_thinking_message(chat_id)
          metadata["thinking_message_id"] = thinking_id.to_s
        end

        @bus.publish_inbound(Bus::InboundMessage.new(
          channel: "telegram",
          sender_id: sender_id,
          chat_id: chat_id,
          content: text,
          session_key: "telegram:#{chat_id}",
          metadata: metadata
        ))
      end

      private def send_thinking_message(chat_id : String) : Int64?
        url = "https://api.telegram.org/bot#{@token}/sendMessage"
        body = {
          "chat_id" => chat_id,
          "text"    => "Processing... 🤔",
        }.to_json

        begin
          response = HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          if response.success?
            data = JSON.parse(response.body)
            data.dig?("result", "message_id").try(&.as_i64?)
          end
        rescue ex
          Logger.warn("telegram", "Failed to send thinking message: #{ex.message}")
          nil
        end
      end

      private def get_bot_username : String
        url = "https://api.telegram.org/bot#{@token}/getMe"
        response = HTTP::Client.get(url)
        if response.success?
          data = JSON.parse(response.body)
          data.dig?("result", "username").try(&.as_s?) || "bot"
        else
          "bot"
        end
      end

      def edit_message(chat_id : String, message_id : Int64, text : String)
        # Split long messages — edit only the first chunk, send rest as new
        chunks = split_message(text, 4096)

        # Edit the thinking message with the first chunk
        edit_url = "https://api.telegram.org/bot#{@token}/editMessageText"
        escaped = escape_markdown_v2(chunks[0])
        body = {
          "chat_id"    => chat_id,
          "message_id" => message_id,
          "text"       => escaped,
          "parse_mode" => "MarkdownV2",
        }.to_json

        begin
          response = HTTP::Client.post(edit_url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          unless response.success?
            # Retry without markdown
            body_plain = {
              "chat_id"    => chat_id,
              "message_id" => message_id,
              "text"       => chunks[0],
            }.to_json
            response = HTTP::Client.post(edit_url,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: body_plain
            )
            # If edit still fails, fall back to sendMessage
            unless response.success?
              send_message(chat_id, text)
              return
            end
          end
        rescue ex
          Logger.warn("telegram", "Failed to edit message, falling back to send: #{ex.message}")
          send_message(chat_id, text)
          return
        end

        # Send remaining chunks as new messages
        if chunks.size > 1
          chunks[1..].each do |chunk|
            send_single_chunk(chat_id, chunk)
          end
        end
      end

      def send_message(chat_id : String, text : String)
        # Split long messages (Telegram limit: 4096 chars)
        chunks = split_message(text, 4096)
        chunks.each do |chunk|
          send_single_chunk(chat_id, chunk)
        end
      end

      private def send_single_chunk(chat_id : String, chunk : String)
        url = "https://api.telegram.org/bot#{@token}/sendMessage"
        escaped = escape_markdown_v2(chunk)
        body = {
          "chat_id"    => chat_id,
          "text"       => escaped,
          "parse_mode" => "MarkdownV2",
        }.to_json

        begin
          response = HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          unless response.success?
            # Retry without markdown on parse error
            body_plain = {
              "chat_id" => chat_id,
              "text"    => chunk,
            }.to_json
            HTTP::Client.post(url,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: body_plain
            )
          end
        rescue ex
          # Retry without markdown on parse error
          body_plain = {
            "chat_id" => chat_id,
            "text"    => chunk,
          }.to_json
          HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body_plain
          )
        end
      end

      # Escape text for Telegram MarkdownV2 format.
      # Preserves code blocks (``` and `) and bold (**) formatting,
      # escapes all other special characters.
      private def escape_markdown_v2(text : String) : String
        result = String::Builder.new
        i = 0
        chars = text

        while i < chars.size
          # Preserve fenced code blocks (```...```)
          if i + 2 < chars.size && chars[i] == '`' && chars[i + 1] == '`' && chars[i + 2] == '`'
            end_pos = chars.index("```", i + 3)
            if end_pos
              result << chars[i..end_pos + 2]
              i = end_pos + 3
              next
            end
          end

          # Preserve inline code (`...`)
          if chars[i] == '`'
            end_pos = chars.index('`', i + 1)
            if end_pos
              result << chars[i..end_pos]
              i = end_pos + 1
              next
            end
          end

          # Convert ** bold to * bold (MarkdownV2 uses single *)
          if i + 1 < chars.size && chars[i] == '*' && chars[i + 1] == '*'
            result << '*'
            i += 2
            next
          end

          # Escape MarkdownV2 special chars (except those we handle above)
          if "_[]()~>#+-=|{}.!\\".includes?(chars[i])
            result << '\\'
            result << chars[i]
            i += 1
            next
          end

          result << chars[i]
          i += 1
        end

        result.to_s
      end

      private def split_message(text : String, max_length : Int32) : Array(String)
        return [text] if text.size <= max_length
        chunks = [] of String
        while text.size > max_length
          # Try to split at newline
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
