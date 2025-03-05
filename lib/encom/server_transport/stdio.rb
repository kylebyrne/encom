# frozen_string_literal: true

require 'json'
require 'encom/server_transport/base'

module Encom
  module ServerTransport
    class Stdio < Base
      def start
        debug 'Starting StdIO transport server'
        debug 'Listening on stdin, writing to stdout...'

        # Enable line buffering for stdout
        $stdout.sync = true

        # Set up signal handlers for graceful shutdown
        setup_signal_handlers

        @running = true

        # Process messages until stdin is closed or shutdown is requested
        while @running && (line = $stdin.gets)
          begin
            message = JSON.parse(line, symbolize_names: true)
            debug "Received: #{message.inspect}"
            process_message(message)
          rescue JSON::ParserError => e
            debug "Error parsing message: #{e.message}"
            next
          rescue StandardError => e
            debug "Error processing message: #{e.message}"
            next
          end
        end

        debug 'StdIO transport server stopped'
      end

      def stop
        debug 'Stopping StdIO transport server'
        @running = false
        # No specific cleanup needed for stdio beyond setting running to false
      end

      def send_message(message)
        json = JSON.generate(message)
        debug "Sending: #{message.inspect}"
        puts json # Write to stdout
        $stdout.flush
        true
      end

      def debug(message)
        return unless @debug

        warn "[Encom::ServerTransport::Stdio] #{message}"
      end

      private

      def setup_signal_handlers
        # Handle INT (CTRL+C) and TERM signals for graceful shutdown
        trap('INT') { handle_signal('INT') }
        trap('TERM') { handle_signal('TERM') }
      end

      def handle_signal(signal)
        debug "Received #{signal} signal, shutting down..."
        stop
      end
    end
  end
end
