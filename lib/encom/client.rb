require "json"
module Encom
  class Client
    LATEST_PROTOCOL_VERSION = '2024-11-05'
    SUPPORTED_PROTOCOL_VERSIONS = [
      LATEST_PROTOCOL_VERSION
      # Add more supported versions as they're developed
    ].freeze

    class ProtocolVersionError < StandardError; end
    class ConnectionError < StandardError; end
    class ToolError < StandardError; end
    class RequestTimeoutError < StandardError; end

    attr_reader :name, :version, :responses, :server_info, :server_capabilities,
                :initialized, :protocol_version, :tool_responses

    def initialize(name:, version:, capabilities:)
      @name = name
      @version = version
      @capabilities = capabilities
      @message_id = 0
      @responses = []
      @tool_responses = {}
      @pending_requests = {}
      @response_mutex = Mutex.new
      @response_condition = ConditionVariable.new
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
    rescue JSON::ParserError => e
      # This might be a protocol version error or other startup error
      trigger_error(ConnectionError.new("Error parsing initial response: #{e.message}"))
    end

    def handle_transport_error(error)
      trigger_error(ConnectionError.new("Transport error: #{error.message}"))
    end

    def handle_response(data)
      data = data.strip if data.is_a?(String)
      parsed_response = JSON.parse(data, symbolize_names: true)

      @responses << parsed_response

      # Check for protocol errors immediately, even without an ID
      if parsed_response[:error] && 
         parsed_response[:error][:code] == -32001 && # PROTOCOL_ERROR 
         parsed_response[:error][:message].include?("Unsupported protocol version")
        error = ProtocolVersionError.new(parsed_response[:error][:message])
        close
        trigger_error(error)
        return
      end

      if parsed_response[:id]
        @response_mutex.synchronize do
          @tool_responses[parsed_response[:id]] = parsed_response
          @response_condition.broadcast # Signal threads waiting for this response
        end

        if parsed_response[:result]
          handle_initialize_result(parsed_response) if @pending_requests[parsed_response[:id]] == 'initialize'
        elsif parsed_response[:error]
          handle_error(parsed_response)
        end
      end
    rescue JSON::ParserError => e
      error_msg = "Error parsing response: #{e.message}, Raw response: #{data.inspect}"
      trigger_error(ConnectionError.new(error_msg))
    end

    def handle_initialize_result(response)
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
      # Check if this is an error response to an initialize request
      if @pending_requests[response[:id]] == 'initialize' && 
         response[:error][:code] == -32001 # PROTOCOL_ERROR
        puts "DEBUG: Protocol error received in initialize response: #{response[:error].inspect}"
        error = ProtocolVersionError.new("Unsupported protocol version: #{response[:error][:message]}")
        puts "DEBUG: Creating ProtocolVersionError: #{error.inspect}"
        close
        trigger_error(error)
        return
      end

      error_msg = "Error from server: #{response[:error][:message]} (#{response[:error][:code]})"
      puts "DEBUG: General error received: #{error_msg}"
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
      id = @message_id

      @pending_requests[id] = request_data[:method]

      @transport.send(
        JSON.generate({
          jsonrpc: '2.0',
          id: id
        }.merge(request_data))
      )

      id
    end

    def notification(notification_data)
      @transport.send(
        JSON.generate({
          jsonrpc: '2.0'
        }.merge(notification_data))
      )
    end

    # Wait for a response with a specific ID, with timeout
    #
    # @param id [Integer] The ID of the request to wait for
    # @param timeout [Numeric] The timeout in seconds
    # @return [Hash] The response
    # @raise [RequestTimeoutError] If the timeout is reached
    def wait_for_response(id, timeout = 5)
      deadline = Time.now + timeout

      @response_mutex.synchronize do
        @response_condition.wait(@response_mutex, 0.1) while !@tool_responses.key?(id) && Time.now < deadline

        raise RequestTimeoutError, "Timeout waiting for response to request #{id}" unless @tool_responses.key?(id)

        @tool_responses[id]
      end
    end

    # List available tools from the server
    #
    # @param params [Hash, nil] Optional parameters for the list_tools request
    # @param timeout [Numeric] The timeout in seconds
    # @return [Array<Hash>] The list of tools
    # @raise [RequestTimeoutError] If the timeout is reached
    # @raise [ConnectionError] If there is an error communicating with the server
    def list_tools(params = nil, timeout = 5)
      request_data = {
        method: 'tools/list'
      }

      request_data[:params] = params if params

      id = request(request_data)

      # Wait for the response
      response = wait_for_response(id, timeout)

      if response[:error]
        error_msg = "Error from server: #{response[:error][:message]} (#{response[:error][:code]})"
        raise ConnectionError, error_msg
      end

      # Return the tools array
      response[:result][:tools]
    end

    # Call a tool on the server
    #
    # @param name [String] The name of the tool to call
    # @param arguments [Hash] The arguments to pass to the tool
    # @param timeout [Numeric] The timeout in seconds
    # @return [Hash] The tool result containing content array
    # @raise [RequestTimeoutError] If the timeout is reached
    # @raise [ToolError] If there is an error with the tool execution
    # @raise [ConnectionError] If there is an error communicating with the server
    def call_tool(name:, arguments:, timeout: 5)
      id = request(
        {
          method: 'tools/call',
          params: {
            name: name,
            arguments: arguments
          }
        }
      )

      # Wait for the response
      response = wait_for_response(id, timeout)

      if response[:error]
        error_msg = "Tool error: #{response[:error][:message]} (#{response[:error][:code]})"
        raise ToolError, error_msg
      end

      # Return the result content
      response[:result]
    end

    # Get the list of tools from a previous list_tools request
    #
    # @param request_id [Integer] The ID of the list_tools request
    # @return [Array<Hash>, nil] The list of tools or nil if the response isn't available
    def get_tools(request_id)
      response = @tool_responses[request_id]
      return nil unless response && response[:result]

      response[:result][:tools]
    end

    # Get the result of a tool call
    #
    # @param request_id [Integer] The ID of the call_tool request
    # @return [Hash, nil] The tool result or nil if the response isn't available
    def get_tool_result(request_id)
      response = @tool_responses[request_id]
      return nil unless response

      if response[:error]
        error_msg = "Tool error: #{response[:error][:message]} (#{response[:error][:code]})"
        raise ToolError, error_msg
      end

      response[:result]
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
