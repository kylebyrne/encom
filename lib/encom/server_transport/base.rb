# frozen_string_literal: true

module Encom
  module ServerTransport
    class Base
      attr_reader :server

      def initialize(server, options = {})
        @server = server
        @options = options
        @debug = options[:debug] || false
      end

      # Start the transport - must be implemented by subclasses
      def start
        raise NotImplementedError, 'Subclasses must implement #start'
      end

      # Stop the transport - must be implemented by subclasses
      def stop
        raise NotImplementedError, 'Subclasses must implement #stop'
      end

      # Send a message through the transport - must be implemented by subclasses
      def send_message(message)
        raise NotImplementedError, 'Subclasses must implement #send_message'
      end

      # Process an incoming message - default implementation delegates to server
      def process_message(message)
        @server.process_message(message)
      end

      # Log debug information if debug is enabled
      def debug(message)
        return unless @debug

        warn "[Encom::ServerTransport] #{message}"
      end
    end
  end
end
