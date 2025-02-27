# frozen_string_literal: true

require 'encom/client'
require 'encom/transport/stdio'
require 'json'

RSpec.describe Encom do
  describe 'client initialization' do
    let(:client) do
      Encom::Client.new(
        name: 'ExampleClient',
        version: '1.0.0',
        capabilities: {
          roots: {
            listChanged: true
          },
          sampling: {},
          tools: {
            execute: true
          }
        }
      )
    end

    it 'initializes connection with mock server' do
      mock_server_path = File.expand_path('../bin/mock_mcp_server', __dir__)

      # Set up error handling
      errors = []
      client.on_error { |error| errors << error }

      transport = Encom::Transport::Stdio.new(
        command: mock_server_path,
        args: []
      )

      client.connect(transport)

      # Wait for server response and client processing
      sleep(1)

      # Verify no errors occurred
      expect(errors).to be_empty

      # Verify client is properly initialized
      expect(client.initialized).to be true

      expect(client.server_info).to eq(
        {
          name: 'MockMCPServer',
          version: '1.0.0'
        }
      )

      expect(client.server_capabilities).to eq(
        {
          roots: {
            listChanged: true
          },
          sampling: {},
          tools: {}
        }
      )

      expect(client.protocol_version).to eq('2024-11-05')
    end

    it 'reports error when server returns unsupported protocol version' do
      mock_server_path = File.expand_path('../bin/mock_mcp_server', __dir__)

      errors = []
      client.on_error { |error| errors << error }

      transport = Encom::Transport::Stdio.new(
        command: mock_server_path,
        args: ['--protocol-version', 'invalid-protocol']
      )

      client.connect(transport)

      # Wait for error to be reported
      sleep(1)

      expect(errors.size).to eq(1)
      expect(errors.first).to be_a(Encom::Client::ProtocolVersionError)
      expect(errors.first.message).to match(/Unsupported protocol version: invalid-protocol/)

      expect(client.initialized).to be false
    end
  end

  describe 'tool functionality' do
    let(:client) do
      Encom::Client.new(
        name: 'ExampleClient',
        version: '1.0.0',
        capabilities: {
          tools: {
            execute: true
          }
        }
      )
    end

    before(:each) do
      mock_server_path = File.expand_path('../bin/mock_mcp_server', __dir__)

      transport = Encom::Transport::Stdio.new(
        command: mock_server_path,
        args: []
      )

      client.connect(transport)

      # Wait for initialization to complete
      sleep(1)
    end

    it 'can list available tools' do
      tools = client.list_tools
      expect(tools).to eq(
        [
          {
            name: 'calculate_sum',
            description: 'Add two numbers together',
            inputSchema: {
              type: 'object',
              properties: {
                a: { type: 'number' },
                b: { type: 'number' }
              },
              required: %w[a b]
            }
          },
          {
            name: 'echo',
            description: 'Echo back the input message',
            inputSchema: {
              type: 'object',
              properties: {
                message: { type: 'string' }
              },
              required: ['message']
            }
          }
        ]
      )
    end

    it 'can call the calculate_sum tool with arguments' do
      result = client.call_tool(
        name: 'calculate_sum',
        arguments: { a: 5, b: 3 }
      )

      expect(result).to eq(
        {
          content: [
            {
              type: 'text',
              text: 'The sum of 5 and 3 is 8'
            }
          ]
        }
      )
    end

    it 'can call the echo tool with a message' do
      result = client.call_tool(
        name: 'echo',
        arguments: { message: 'Hello, MCP!' }
      )

      expect(result).to eq(
        {
          content: [
            {
              type: 'text',
              text: 'Echo: Hello, MCP!'
            }
          ]
        }
      )
    end
  end
end
