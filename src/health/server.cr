require "http/server"
require "json"

module CrystalClaw
  module Health
    class Server
      @host : String
      @port : Int32
      @server : HTTP::Server?

      def initialize(@host = "0.0.0.0", @port = 18791)
      end

      def start
        handlers = HTTP::Server.new do |context|
          case context.request.path
          when "/health"
            context.response.content_type = "application/json"
            context.response.print({"status" => "ok", "timestamp" => Time.utc.to_unix}.to_json)
          when "/ready"
            context.response.content_type = "application/json"
            context.response.print({"ready" => true}.to_json)
          else
            context.response.status = HTTP::Status::NOT_FOUND
            context.response.print "Not Found"
          end
        end

        @server = handlers
        handlers.bind_tcp(@host, @port)
        spawn do
          handlers.listen
        end
      end

      def stop
        @server.try(&.close)
      end
    end
  end
end
