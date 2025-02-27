module Encom
  class Client
    LATEST_PROTOCOL_VERSION = '2024-11-05'
    SUPPORTED_PROTOCOL_VERSIONS = [
      LATEST_PROTOCOL_VERSION
      # Add more supported versions as they're developed
    ].freeze

    class ProtocolVersionError < StandardError; end
    class ConnectionError < StandardError; end

    attr_reader :name, :version, :responses, :server_info, :server_capabilities, :initialized, :protocol_version

    def initialize(name:, version:, capabilities:)
      @name = name
      @version = version
      @capabilities = capabilities
      @message_id = 0
      @responses = []
      @initialized = false
      @closing = false
      @error_handlers = []
    end

    # Register a callback for error handling
    def on_error(&block)
      @error_handlers << block
      self
    end

    def connect(transport)
      @transport = transport

      @transport
        .on_close { close }
        .on_data { |data| handle_response(data) }
        .on_error { |error| handle_transport_error(error) }
        .start

      # Send initialize request
      request(
        {
          method: 'initialize',
          params: {
            protocolVersion: LATEST_PROTOCOL_VERSION,
            capabilities: @capabilities,
            clientInfo: {
              name: @name,
              version: @version
            }
          }
        }
      )

      self # Return self for method chaining
    end

    def handle_transport_error(error)
      trigger_error(ConnectionError.new("Transport error: #{error.message}"))
    end

    def handle_response(data)
      data = data.strip if data.is_a?(String)
      parsed_response = JSON.parse(data, symbolize_names: true)

      @responses << parsed_response

      if parsed_response[:id] && parsed_response[:result]
        handle_result(parsed_response)
      elsif parsed_response[:id] && parsed_response[:error]
        handle_error(parsed_response)
      end
    rescue JSON::ParserError => e
      error_msg = "Error parsing response: #{e.message}, Raw response: #{data.inspect}"
      trigger_error(ConnectionError.new(error_msg))
    end

    def handle_result(response)
      @server_info = response[:result][:serverInfo]
      @server_capabilities = response[:result][:capabilities]
      @protocol_version = response[:result][:protocolVersion]

      unless SUPPORTED_PROTOCOL_VERSIONS.include?(@protocol_version)
        error_message = "Unsupported protocol version: #{@protocol_version}. " \
                        "This client supports: #{SUPPORTED_PROTOCOL_VERSIONS.join(', ')}"
        error = ProtocolVersionError.new(error_message)
        close
        trigger_error(error)
        return
      end

      @initialized = true

      notification(
        {
          method: 'initialized',
          params: {}
        }
      )
    end

    def handle_error(response)
      error_msg = "Error from server: #{response[:error][:message]} (#{response[:error][:code]})"
      trigger_error(ConnectionError.new(error_msg))
    end

    def trigger_error(error)
      if @error_handlers.empty?
        # TODO: I'd love to re-raise this to the user but this ends up run
        # in a background thread right now due to how we've implement the stdio transport
        puts "MCP Client Error: #{error.message}"
      else
        @error_handlers.each { |handler| handler.call(error) }
      end
    end

    def request(request_data)
      @message_id += 1

      @transport.send(
        JSON.generate({
          jsonrpc: '2.0',
          id: @message_id
        }.merge(request_data))
      )

      @message_id
    end

    def notification(notification_data)
      @transport.send(
        JSON.generate({
          jsonrpc: '2.0'
        }.merge(notification_data))
      )
    end

    def close
      return if @closing

      @closing = true
      puts 'Closing'

      return unless @transport

      @transport.close
      @transport = nil
    end
  end
end
