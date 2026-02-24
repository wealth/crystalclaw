require "http/client"
require "json"
require "mime"
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

        @bus.publish_inbound(Bus::InboundMessage.new(
          channel: "telegram",
          sender_id: sender_id,
          chat_id: chat_id,
          content: text,
          session_key: "telegram:#{chat_id}"
        ))
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

      def send_message(chat_id : String, text : String)
        escaped = escape_markdown_v2(text)
        chunks = split_message(escaped, 4096)
        chunks.each do |chunk|
          send_single_chunk(chat_id, chunk)
        end
      end

      # Send a chunk that is already escaped for MarkdownV2
      private def send_single_chunk(chat_id : String, chunk : String)
        url = "https://api.telegram.org/bot#{@token}/sendMessage"
        body = {
          "chat_id"    => chat_id,
          "text"       => chunk,
          "parse_mode" => "MarkdownV2",
        }.to_json

        begin
          response = HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "application/json"},
            body: body
          )
          unless response.success?
            # Retry as plain text (strip markdown)
            body_plain = {
              "chat_id" => chat_id,
              "text"    => strip_markdown(chunk),
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

      def send_photo(chat_id : String, photo : String)
        if photo.starts_with?("http://") || photo.starts_with?("https://")
          url = "https://api.telegram.org/bot#{@token}/sendPhoto"
          body = {
            "chat_id" => chat_id,
            "photo"   => photo,
          }.to_json
          HTTP::Client.post(url, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: body)
        else
          send_file_multipart("sendPhoto", chat_id, "photo", photo)
        end
      rescue ex
        Logger.warn("telegram", "Failed to send photo: #{ex.message}")
      end

      def send_audio(chat_id : String, audio : String)
        if audio.starts_with?("http://") || audio.starts_with?("https://")
          url = "https://api.telegram.org/bot#{@token}/sendAudio"
          body = {
            "chat_id" => chat_id,
            "audio"   => audio,
          }.to_json
          HTTP::Client.post(url, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: body)
        else
          send_file_multipart("sendAudio", chat_id, "audio", audio)
        end
      rescue ex
        Logger.warn("telegram", "Failed to send audio: #{ex.message}")
      end

      def send_media_group(chat_id : String, media : Array(JSON::Any))
        has_local = media.any? { |m| m["url"]? && !m["url"].as_s.starts_with?("http") }

        if !has_local
          url = "https://api.telegram.org/bot#{@token}/sendMediaGroup"
          media_payload = media.map do |m|
            {
              "type"  => m["type"]?.try(&.as_s?) || "photo",
              "media" => m["url"]?.try(&.as_s?) || "",
            }
          end

          body = {
            "chat_id" => chat_id,
            "media"   => media_payload,
          }.to_json

          HTTP::Client.post(url, headers: HTTP::Headers{"Content-Type" => "application/json"}, body: body)
        else
          send_media_group_multipart(chat_id, media)
        end
      rescue ex
        Logger.warn("telegram", "Failed to send media group: #{ex.message}")
      end

      private def send_file_multipart(endpoint : String, chat_id : String, file_field : String, file_path : String)
        return unless File.exists?(file_path)
        url = "https://api.telegram.org/bot#{@token}/#{endpoint}"

        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.field("chat_id", chat_id)

        File.open(file_path) do |file|
          mime_type = MIME.from_filename(file_path, "application/octet-stream")
          metadata = HTTP::FormData::FileMetadata.new(filename: File.basename(file_path))
          headers = HTTP::Headers{"Content-Type" => mime_type}
          builder.file(file_field, file, metadata, headers)
        end

        builder.finish
        boundary = builder.boundary

        HTTP::Client.post(url,
          headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"},
          body: io.to_s
        )
      end

      private def send_media_group_multipart(chat_id : String, media : Array(JSON::Any))
        url = "https://api.telegram.org/bot#{@token}/sendMediaGroup"
        io = IO::Memory.new
        builder = HTTP::FormData::Builder.new(io)
        builder.field("chat_id", chat_id)

        media_payload = [] of Hash(String, String)
        files_to_close = [] of File

        begin
          media.each_with_index do |m, idx|
            m_url = m["url"]?.try(&.as_s?) || ""
            if m_url.empty?
              next
            end
            m_type = m["type"]?.try(&.as_s?) || "photo"

            if m_url.starts_with?("http://") || m_url.starts_with?("https://")
              media_payload << {"type" => m_type, "media" => m_url}
            elsif File.exists?(m_url)
              attach_name = "file#{idx}"
              media_payload << {"type" => m_type, "media" => "attach://#{attach_name}"}

              file = File.open(m_url)
              files_to_close << file
              mime_type = MIME.from_filename(m_url, "application/octet-stream")
              metadata = HTTP::FormData::FileMetadata.new(filename: File.basename(m_url))
              headers = HTTP::Headers{"Content-Type" => mime_type}
              builder.file(attach_name, file, metadata, headers)
            end
          end

          builder.field("media", media_payload.to_json)
          builder.finish
          boundary = builder.boundary

          HTTP::Client.post(url,
            headers: HTTP::Headers{"Content-Type" => "multipart/form-data; boundary=#{boundary}"},
            body: io.to_s
          )
        ensure
          files_to_close.each(&.close)
        end
      end

      # Escape special characters for Telegram MarkdownV2.
      # Preserves markdown formatting (bold, italic, code, links) but escapes
      # special chars in plain text segments so Telegram doesn't reject the message.
      private def escape_markdown_v2(text : String) : String
        result = String::Builder.new
        i = 0
        lines = text.split('\n')
        line_idx = 0

        while line_idx < lines.size
          line = lines[line_idx]

          # Fenced code blocks — pass through, only escape ` and \ inside
          if line.strip.starts_with?("```")
            result << line << '\n'
            line_idx += 1
            while line_idx < lines.size && !lines[line_idx].strip.starts_with?("```")
              result << lines[line_idx] << '\n'
              line_idx += 1
            end
            if line_idx < lines.size
              result << lines[line_idx] # closing ```
              result << '\n' if line_idx + 1 < lines.size
              line_idx += 1
            end
            next
          end

          # Regular line — escape special chars outside of inline formatting
          result << escape_line_markdown_v2(line)
          result << '\n' if line_idx + 1 < lines.size
          line_idx += 1
        end

        result.to_s
      end

      # Escape a single line for MarkdownV2, preserving inline formatting
      private def escape_line_markdown_v2(line : String) : String
        result = String::Builder.new
        i = 0

        while i < line.size
          # Inline code `...` — pass through, content doesn't need escaping
          if line[i] == '`'
            end_pos = line.index('`', i + 1)
            if end_pos
              result << line[i..end_pos]
              i = end_pos + 1
              next
            end
          end

          # Markdown links [text](url) — escape text part, pass url through
          if line[i] == '['
            close_bracket = line.index(']', i + 1)
            if close_bracket && close_bracket + 1 < line.size && line[close_bracket + 1] == '('
              close_paren = line.index(')', close_bracket + 2)
              if close_paren
                link_text = line[(i + 1)...close_bracket]
                link_url = line[(close_bracket + 2)...close_paren]
                result << '[' << escape_plain_text_v2(link_text) << "](" << link_url << ')'
                i = close_paren + 1
                next
              end
            end
          end

          # Bold **text**
          if i + 1 < line.size && line[i] == '*' && line[i + 1] == '*'
            end_pos = line.index("**", i + 2)
            if end_pos
              content = line[(i + 2)...end_pos]
              result << "**" << escape_plain_text_v2(content) << "**"
              i = end_pos + 2
              next
            end
          end

          # Bold __text__
          if i + 1 < line.size && line[i] == '_' && line[i + 1] == '_'
            end_pos = line.index("__", i + 2)
            if end_pos
              content = line[(i + 2)...end_pos]
              result << "__" << escape_plain_text_v2(content) << "__"
              i = end_pos + 2
              next
            end
          end

          # Strikethrough ~~text~~
          if i + 1 < line.size && line[i] == '~' && line[i + 1] == '~'
            end_pos = line.index("~~", i + 2)
            if end_pos
              content = line[(i + 2)...end_pos]
              result << "~~" << escape_plain_text_v2(content) << "~~"
              i = end_pos + 2
              next
            end
          end

          # Italic *text* (single, not **)
          if line[i] == '*' && (i + 1 < line.size && line[i + 1] != '*')
            end_pos = line.index('*', i + 1)
            if end_pos && end_pos > i + 1
              content = line[(i + 1)...end_pos]
              result << '*' << escape_plain_text_v2(content) << '*'
              i = end_pos + 1
              next
            end
          end

          # Italic _text_ (single, not __)
          if line[i] == '_' && (i + 1 < line.size && line[i + 1] != '_')
            end_pos = line.index('_', i + 1)
            if end_pos && end_pos > i + 1
              content = line[(i + 1)...end_pos]
              result << '_' << escape_plain_text_v2(content) << '_'
              i = end_pos + 1
              next
            end
          end

          # Plain character — escape if special
          result << escape_char_v2(line[i])
          i += 1
        end

        result.to_s
      end

      # Escape a single character for MarkdownV2 plain text context
      private def escape_char_v2(c : Char) : String
        case c
        when '_', '*', '[', ']', '(', ')', '~', '`', '>', '#', '+', '-', '=', '|', '{', '}', '.', '!', '\\'
          "\\#{c}"
        else
          c.to_s
        end
      end

      # Escape all MarkdownV2 special chars in a plain text string
      private def escape_plain_text_v2(text : String) : String
        result = String::Builder.new
        text.each_char { |c| result << escape_char_v2(c) }
        result.to_s
      end

      # Strip markdown formatting for plain-text fallback
      private def strip_markdown(text : String) : String
        text
          .gsub(/```[\s\S]*?```/) { |m| m.gsub("```", "") } # code blocks
          .gsub(/`([^`]+)`/, "\\1")                         # inline code
          .gsub(/\*\*([^*]+)\*\*/, "\\1")                   # bold
          .gsub(/__([^_]+)__/, "\\1")                       # bold
          .gsub(/\*([^*]+)\*/, "\\1")                       # italic
          .gsub(/_([^_]+)_/, "\\1")                         # italic
          .gsub(/~~([^~]+)~~/, "\\1")                       # strikethrough
          .gsub(/\[([^\]]+)\]\([^)]+\)/, "\\1")             # links
          .gsub(/^\#{1,6}\s+/, "")                          # headers
          .gsub(/\\(.)/, "\\1")                             # unescape
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
