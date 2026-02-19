require "json"
require "http/client"
require "uri"
require "./base"

module CrystalClaw
  module Tools
    class WebSearchTool < Tool
      @brave_api_key : String
      @brave_max_results : Int32
      @brave_enabled : Bool
      @ddg_max_results : Int32
      @ddg_enabled : Bool

      def initialize(
        @brave_api_key = "",
        @brave_max_results = 5,
        @brave_enabled = false,
        @ddg_max_results = 5,
        @ddg_enabled = true,
      )
      end

      def name : String
        "web_search"
      end

      def description : String
        "Search the web for information. Returns a list of relevant results with titles, URLs, and snippets."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"query":{"type":"string","description":"The search query"}},"required":["query"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        query = args["query"]?.try(&.as_s?) || return ToolResult.error("Missing 'query' argument")

        if @brave_enabled && !@brave_api_key.empty?
          brave_search(query)
        elsif @ddg_enabled
          duckduckgo_search(query)
        else
          ToolResult.error("No search provider configured")
        end
      end

      private def brave_search(query : String) : ToolResult
        begin
          encoded = URI.encode_www_form(query)
          headers = HTTP::Headers{
            "Accept"               => "application/json",
            "Accept-Encoding"      => "gzip",
            "X-Subscription-Token" => @brave_api_key,
          }

          response = HTTP::Client.get(
            "https://api.search.brave.com/res/v1/web/search?q=#{encoded}&count=#{@brave_max_results}",
            headers: headers
          )

          unless response.success?
            return ToolResult.error("Brave search error: HTTP #{response.status_code}")
          end

          data = JSON.parse(response.body)
          results = data.dig?("web", "results")
          return ToolResult.success("No results found for: #{query}") unless results

          result_text = String.build do |str|
            results.as_a.each_with_index do |r, i|
              title = r["title"]?.try(&.as_s?) || "No title"
              url = r["url"]?.try(&.as_s?) || ""
              desc = r["description"]?.try(&.as_s?) || ""
              str << "#{i + 1}. #{title}\n   #{url}\n   #{desc}\n\n"
            end
          end

          ToolResult.success(result_text)
        rescue ex
          ToolResult.error("Brave search error: #{ex.message}")
        end
      end

      private def duckduckgo_search(query : String) : ToolResult
        begin
          encoded = URI.encode_www_form(query)
          response = HTTP::Client.get("https://html.duckduckgo.com/html/?q=#{encoded}")

          unless response.success?
            return ToolResult.error("DuckDuckGo search error: HTTP #{response.status_code}")
          end

          # Parse HTML results (simple extraction)
          body = response.body
          results = [] of String
          count = 0

          # Extract result snippets from DDG HTML
          body.scan(/class="result__a"[^>]*href="([^"]*)"[^>]*>([^<]*)</) do |m|
            break if count >= @ddg_max_results
            url = m[1]
            title = m[2].strip
            # Try to get the URL from uddg param
            if url.includes?("uddg=")
              if actual = URI.decode_www_form(url.split("uddg=").last.split("&").first)
                url = actual
              end
            end
            results << "#{count + 1}. #{title}\n   #{url}"
            count += 1
          end

          if results.empty?
            # Fallback message with helpful links
            ToolResult.success("No search results found. Try searching manually:\n" \
                               "- https://duckduckgo.com/?q=#{encoded}\n" \
                               "- https://www.google.com/search?q=#{encoded}")
          else
            ToolResult.success(results.join("\n\n"))
          end
        rescue ex
          ToolResult.error("DuckDuckGo search error: #{ex.message}")
        end
      end
    end

    class WebFetchTool < Tool
      @max_length : Int32

      def initialize(@max_length = 50_000)
      end

      def name : String
        "web_fetch"
      end

      def description : String
        "Fetch the text content of a web page. Returns the page text (HTML tags stripped)."
      end

      def parameters : Hash(String, JSON::Any)
        JSON.parse(%({"type":"object","properties":{"url":{"type":"string","description":"The URL to fetch"}},"required":["url"]})).as_h
      end

      def execute(args : Hash(String, JSON::Any)) : ToolResult
        url = args["url"]?.try(&.as_s?) || return ToolResult.error("Missing 'url' argument")

        begin
          response = HTTP::Client.get(url, headers: HTTP::Headers{
            "User-Agent" => "CrystalClaw/0.1 (AI Assistant Bot)",
          })

          unless response.success?
            return ToolResult.error("HTTP error #{response.status_code} for #{url}")
          end

          text = strip_html(response.body)
          if text.bytesize > @max_length
            text = text[0, @max_length] + "\n... (content truncated)"
          end
          ToolResult.success(text)
        rescue ex
          ToolResult.error("Error fetching URL: #{ex.message}")
        end
      end

      private def strip_html(html : String) : String
        # Remove scripts and styles
        text = html.gsub(/<script[^>]*>.*?<\/script>/mi, "")
        text = text.gsub(/<style[^>]*>.*?<\/style>/mi, "")
        # Remove HTML tags
        text = text.gsub(/<[^>]+>/, " ")
        # Decode common entities
        text = text.gsub("&amp;", "&")
        text = text.gsub("&lt;", "<")
        text = text.gsub("&gt;", ">")
        text = text.gsub("&quot;", "\"")
        text = text.gsub("&#39;", "'")
        text = text.gsub("&nbsp;", " ")
        # Collapse whitespace
        text = text.gsub(/\s+/, " ").strip
        # Restore paragraph breaks
        text = text.gsub(/\s{2,}/, "\n\n")
        text
      end
    end
  end
end
