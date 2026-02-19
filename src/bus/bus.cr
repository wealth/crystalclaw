module CrystalClaw
  module Bus
    struct InboundMessage
      property channel : String
      property sender_id : String
      property chat_id : String
      property content : String
      property session_key : String
      property metadata : Hash(String, String)

      def initialize(
        @channel = "",
        @sender_id = "",
        @chat_id = "",
        @content = "",
        @session_key = "",
        @metadata = {} of String => String,
      )
      end
    end

    struct OutboundMessage
      property channel : String
      property chat_id : String
      property content : String
      property metadata : Hash(String, String)

      def initialize(@channel = "", @chat_id = "", @content = "", @metadata = {} of String => String)
      end
    end

    class MessageBus
      @inbound : Channel(InboundMessage)
      @outbound : Channel(OutboundMessage)
      @outbound_handler : Proc(OutboundMessage, Nil)?

      def initialize(buffer_size = 64)
        @inbound = Channel(InboundMessage).new(buffer_size)
        @outbound = Channel(OutboundMessage).new(buffer_size)
        @outbound_handler = nil
      end

      def publish_inbound(msg : InboundMessage)
        @inbound.send(msg)
      end

      def consume_inbound : InboundMessage?
        select
        when msg = @inbound.receive
          msg
        else
          nil
        end
      end

      def consume_inbound_blocking : InboundMessage
        @inbound.receive
      end

      def publish_outbound(msg : OutboundMessage)
        handler = @outbound_handler
        if handler
          handler.call(msg)
        else
          @outbound.send(msg)
        end
      end

      def consume_outbound : OutboundMessage?
        select
        when msg = @outbound.receive
          msg
        else
          nil
        end
      end

      def on_outbound(&block : OutboundMessage -> Nil)
        @outbound_handler = block
      end
    end
  end
end
