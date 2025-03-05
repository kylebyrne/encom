require 'encom/server/tool'
require 'json'

module Encom
  class Server
    LATEST_PROTOCOL_VERSION = '2024-11-05'
    SUPPORTED_PROTOCOL_VERSIONS = [
      LATEST_PROTOCOL_VERSION
      # Add more supported versions as they're developed
    ].freeze

    class << self
      def name(server_name = nil)
        @server_name ||= server_name
      end

      def version(version = nil)
        @version ||= version
      end

      def tool(tool_name, description, schema, proc)
        @tools ||= []
        @tools << Tool.new(name: tool_name, description:, schema:, proc:)
      end

      attr_reader :tools
    end

    attr_reader :transport, :capabilities

    # Define standard JSON-RPC error codes
    module ErrorCodes
      PARSE_ERROR = -32700
      INVALID_REQUEST = -32600
      METHOD_NOT_FOUND = -32601
      INVALID_PARAMS = -32602
      INTERNAL_ERROR = -32603
      
      # MCP specific error codes
      TOOL_EXECUTION_ERROR = -32000
      PROTOCOL_ERROR = -32001
    end

    def initialize(options = {})
      @message_id = 0
      @capabilities = options[:capabilities] || {
        roots: {
          listChanged: true
        },
        sampling: {},
        tools: {}
      }
      
      # Validate protocol version immediately
      protocol_version = options[:protocol_version] || LATEST_PROTOCOL_VERSION
      unless SUPPORTED_PROTOCOL_VERSIONS.include?(protocol_version)
        raise ArgumentError, "Unsupported protocol version: #{protocol_version}. Supported versions: #{SUPPORTED_PROTOCOL_VERSIONS.join(', ')}"
      end
      
      @protocol_version = protocol_version
      @transport = nil
    end

    def name
      self.class.name
    end

    def version
      self.class.version
    end

    def tools
      self.class.tools
    end

    def call_tool(name, arguments)
      tool = tools.find { |t| t.name.to_s == name.to_s || t.name == name.to_sym }
      raise "Unknown tool: #{name}" unless tool
      tool.call(arguments)
    end

    # Run the server with the specified transport
    def run(transport_class, transport_options = {})
      @transport = transport_class.new(self, transport_options)
      @transport.start
    rescue StandardError => e
      $stderr.puts "Error running server: #{e.message}"
      $stderr.puts e.backtrace.join("\n") if transport_options[:debug]
      raise
    end

    # Process incoming JSON-RPC message
    def process_message(message)
      return unless message.is_a?(Hash)

      if @transport && @transport.respond_to?(:debug)
        @transport.debug "Processing message: #{message.inspect}"
      end

      # Check for jsonrpc version
      unless message[:jsonrpc] == '2.0'
        if message[:id]
          respond_error(message[:id], ErrorCodes::INVALID_REQUEST, 'Invalid JSON-RPC request')
        end
        return
      end

      # Process request by method
      case message[:method]
      when 'initialize'
        handle_initialize(message)
      when 'initialized'
        handle_initialized(message)
      when 'resources/list'
        handle_resources_list(message)
      when 'roots/list'
        handle_roots_list(message)
      when 'sampling/prepare'
        handle_sampling_prepare(message)
      when 'sampling/sample'
        handle_sampling_sample(message)
      when 'tools/list'
        handle_tools_list(message)
      when 'tools/call'
        handle_tools_call(message)
      when 'shutdown'
        handle_shutdown(message)
      else
        if message[:id]
          if @transport && @transport.respond_to?(:debug)
            @transport.debug "Unknown method: #{message[:method]}"
          end
          respond_error(message[:id], ErrorCodes::METHOD_NOT_FOUND, "Method not found: #{message[:method]}")
        end
      end
    rescue StandardError => e
      if @transport && @transport.respond_to?(:debug)
        @transport.debug "Error processing message: #{e.message}\n#{e.backtrace.join("\n")}"
      end
      
      if message && message[:id]
        respond_error(message[:id], ErrorCodes::INTERNAL_ERROR, "Internal error: #{e.message}")
      end
    end

    # Generate and send a JSON-RPC response
    def respond(id, result)
      return unless @transport

      response = {
        jsonrpc: "2.0",
        id: id,
        result: result
      }

      @transport.send_message(response)
    end

    # Generate and send a JSON-RPC error response
    def respond_error(id, code, message, data = nil)
      return unless @transport

      response = {
        jsonrpc: "2.0",
        id: id,
        error: {
          code: code,
          message: message
        }
      }
      response[:error][:data] = data if data

      @transport.send_message(response)
    end

    # Handle initialize request
    def handle_initialize(message)
      client_protocol_version = message[:params][:protocolVersion]
      client_capabilities = message[:params][:capabilities]
      client_info = message[:params][:clientInfo]

      server_info = {
        name: name,
        version: version
      }

      # Debug log the received protocol version
      if @transport && @transport.respond_to?(:debug)
        @transport.debug "Received initialize request with protocol version: #{client_protocol_version}"
        @transport.debug "Supported protocol versions: #{SUPPORTED_PROTOCOL_VERSIONS.inspect}"
      end

      # Check if the requested protocol version is supported
      if SUPPORTED_PROTOCOL_VERSIONS.include?(client_protocol_version)
        # Use the requested version if supported
        protocol_version = client_protocol_version
        
        if @transport && @transport.respond_to?(:debug)
          @transport.debug "Protocol version #{protocol_version} is supported, sending success response"
        end
        
        # Send initialize response
        respond(message[:id], {
          protocolVersion: protocol_version,
          capabilities: @capabilities,
          serverInfo: server_info
        })
      else
        # Return an error for unsupported protocol versions
        if @transport && @transport.respond_to?(:debug)
          @transport.debug "Protocol version error: Client requested unsupported version #{client_protocol_version}"
        end
        
        respond_error(
          message[:id],
          ErrorCodes::PROTOCOL_ERROR,
          "Unsupported protocol version: #{client_protocol_version}",
          { supportedVersions: SUPPORTED_PROTOCOL_VERSIONS }
        )
      end
    end

    # Handle initialized notification
    def handle_initialized(message)
      # No response needed for notifications
    end

    # Handle resources/list request
    def handle_resources_list(message)
      # Default implementation returns an empty list
      respond(message[:id], {
        resources: []
      })
    end

    # Handle roots/list request
    def handle_roots_list(message)
      # Default implementation returns an empty list
      respond(message[:id], {
        roots: []
      })
    end

    # Handle sampling/prepare request
    def handle_sampling_prepare(message)
      # Default implementation returns a simple response
      respond(message[:id], {
        prepared: false,
        samplingId: nil
      })
    end

    # Handle sampling/sample request
    def handle_sampling_sample(message)
      # Default implementation returns a simple response
      respond(message[:id], {
        completion: "Sampling not implemented",
        completionId: nil
      })
    end

    # Handle tools/list request
    def handle_tools_list(message)
      tool_definitions = tools ? tools.map(&:definition) : []
      
      respond(message[:id], {
        tools: tool_definitions
      })
    end

    # Handle tools/call request
    def handle_tools_call(message)
      tool_name = message[:params][:name]
      arguments = message[:params][:arguments] || {}
      
      begin
        result = call_tool(tool_name, arguments)
        respond(message[:id], result)
      rescue StandardError => e
        respond_error(message[:id], ErrorCodes::TOOL_EXECUTION_ERROR, "Tool execution error: #{e.message}")
      end
    end

    # Handle JSON-RPC shutdown request
    def handle_shutdown(message)
      if message[:id]
        # If it's a request with ID, respond with a success result
        respond(message[:id], {
          shutdown: true
        })
      end
      # Initiate clean shutdown
      shutdown
    end

    # Shutdown the server and clean up
    def shutdown
      return if @shutting_down
      @shutting_down = true
      
      if @transport
        @transport.stop
        @transport = nil
      end
    end
  end
end
