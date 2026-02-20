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
        html = markdown_to_telegram_html(text)
        # Split long messages — edit only the first chunk, send rest as new
        chunks = split_message(html, 4096)

        # Edit the thinking message with the first chunk
        edit_url = "https://api.telegram.org/bot#{@token}/editMessageText"
        body = {
          "chat_id"    => chat_id,
          "message_id" => message_id,
          "text"       => chunks[0],
          "parse_mode" => "HTML",
        }.to_json

        begin
          response = HTTP::Client.post(edit_url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          unless response.success?
            # Retry without formatting
            body_plain = {
              "chat_id"    => chat_id,
              "message_id" => message_id,
              "text"       => text,
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
            send_single_chunk_raw(chat_id, chunk)
          end
        end
      end

      def send_message(chat_id : String, text : String)
        html = markdown_to_telegram_html(text)
        # Split long messages (Telegram limit: 4096 chars)
        chunks = split_message(html, 4096)
        chunks.each do |chunk|
          send_single_chunk_raw(chat_id, chunk)
        end
      end

      # Send a chunk that is already converted to HTML
      private def send_single_chunk_raw(chat_id : String, html_chunk : String)
        url = "https://api.telegram.org/bot#{@token}/sendMessage"
        body = {
          "chat_id"    => chat_id,
          "text"       => html_chunk,
          "parse_mode" => "HTML",
        }.to_json

        begin
          response = HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          unless response.success?
            # Retry as plain text (strip HTML tags)
            plain = html_chunk.gsub(/<[^>]*>/, "")
            body_plain = {
              "chat_id" => chat_id,
              "text"    => plain,
            }.to_json
            HTTP::Client.post(url,
              headers: HTTP::Headers{"Content-Type" => "application/json"},
              body: body_plain
            )
          end
        rescue ex
          Logger.warn("telegram", "Failed to send chunk: #{ex.message}")
        end
      end

      # Convert standard Markdown to Telegram-compatible HTML.
      # Handles: headers, bold, italic, code blocks, inline code, tables, lists.
      private def markdown_to_telegram_html(text : String) : String
        lines = text.split('\n')
        result = [] of String
        i = 0

        while i < lines.size
          line = lines[i]

          # Fenced code blocks (```...```)
          if line.strip.starts_with?("```")
            lang = line.strip.lchop("```").strip
            code_lines = [] of String
            i += 1
            while i < lines.size && !lines[i].strip.starts_with?("```")
              code_lines << escape_html(lines[i])
              i += 1
            end
            i += 1 # skip closing ```
            if lang.empty?
              result << "<pre>#{code_lines.join('\n')}</pre>"
            else
              result << "<pre><code class=\"language-#{escape_html(lang)}\">#{code_lines.join('\n')}</code></pre>"
            end
            next
          end

          # Markdown table: collect all consecutive | lines, render as <pre>
          if line.strip.starts_with?("|") && line.strip.ends_with?("|")
            table_lines = [] of String
            while i < lines.size && lines[i].strip.starts_with?("|") && lines[i].strip.ends_with?("|")
              row = lines[i].strip
              # Skip separator rows (|---|---|)
              unless row.gsub(/[|\-:\s]/, "").empty?
                table_lines << escape_html(row)
              end
              i += 1
            end
            result << "<pre>#{table_lines.join('\n')}</pre>"
            next
          end

          # Headers: ### heading → bold
          if line =~ /^(\#{1,6})\s+(.+)$/
            heading_text = $2.strip
            result << "<b>#{format_inline(heading_text)}</b>"
            i += 1
            next
          end

          # Unordered list items: - item or * item
          if line =~ /^(\s*)[*\-]\s+(.+)$/
            indent = $1.size // 2
            prefix = "  " * indent + "• "
            result << "#{prefix}#{format_inline($2)}"
            i += 1
            next
          end

          # Ordered list items: 1. item
          if line =~ /^(\s*)(\d+)\.\s+(.+)$/
            indent = $1.size // 2
            prefix = "  " * indent + "#{$2}. "
            result << "#{prefix}#{format_inline($3)}"
            i += 1
            next
          end

          # Regular line
          result << format_inline(line)
          i += 1
        end

        result.join('\n')
      end

      # Format inline markdown elements: bold, italic, inline code, links
      private def format_inline(text : String) : String
        result = String::Builder.new
        i = 0

        while i < text.size
          # Inline code `...`
          if text[i] == '`'
            end_pos = text.index('`', i + 1)
            if end_pos
              code_content = text[(i + 1)...end_pos]
              result << "<code>#{escape_html(code_content)}</code>"
              i = end_pos + 1
              next
            end
          end

          # Markdown links [text](url)
          if text[i] == '['
            close_bracket = text.index(']', i + 1)
            if close_bracket && close_bracket + 1 < text.size && text[close_bracket + 1] == '('
              close_paren = text.index(')', close_bracket + 2)
              if close_paren
                link_text = text[(i + 1)...close_bracket]
                link_url = text[(close_bracket + 2)...close_paren]
                result << "<a href=\"#{escape_html(link_url)}\">#{escape_html(link_text)}</a>"
                i = close_paren + 1
                next
              end
            end
          end

          # Bold **text** or __text__
          if i + 1 < text.size && text[i] == '*' && text[i + 1] == '*'
            end_pos = text.index("**", i + 2)
            if end_pos
              bold_content = text[(i + 2)...end_pos]
              result << "<b>#{escape_html(bold_content)}</b>"
              i = end_pos + 2
              next
            end
          end

          if i + 1 < text.size && text[i] == '_' && text[i + 1] == '_'
            end_pos = text.index("__", i + 2)
            if end_pos
              bold_content = text[(i + 2)...end_pos]
              result << "<b>#{escape_html(bold_content)}</b>"
              i = end_pos + 2
              next
            end
          end

          # Italic *text* or _text_ (single)
          if text[i] == '*' && (i + 1 < text.size && text[i + 1] != '*')
            end_pos = text.index('*', i + 1)
            if end_pos && end_pos > i + 1
              italic_content = text[(i + 1)...end_pos]
              result << "<i>#{escape_html(italic_content)}</i>"
              i = end_pos + 1
              next
            end
          end

          if text[i] == '_' && (i + 1 < text.size && text[i + 1] != '_')
            end_pos = text.index('_', i + 1)
            if end_pos && end_pos > i + 1
              italic_content = text[(i + 1)...end_pos]
              result << "<i>#{escape_html(italic_content)}</i>"
              i = end_pos + 1
              next
            end
          end

          # Strikethrough ~~text~~
          if i + 1 < text.size && text[i] == '~' && text[i + 1] == '~'
            end_pos = text.index("~~", i + 2)
            if end_pos
              strike_content = text[(i + 2)...end_pos]
              result << "<s>#{escape_html(strike_content)}</s>"
              i = end_pos + 2
              next
            end
          end

          # Regular character — escape HTML
          result << escape_html(text[i].to_s)
          i += 1
        end

        result.to_s
      end

      # Escape HTML special characters
      private def escape_html(text : String) : String
        text.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;")
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
