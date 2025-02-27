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
          sampling: {}
        }
      )
    end

    it 'initializes connection with mock server' do
      mock_server_path = File.expand_path('../bin/simple_mock_server.rb', __dir__)

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
          name: 'SimpleMockServer',
          version: '1.0.0'
        }
      )

      expect(client.server_capabilities).to eq(
        {
          roots: {
            listChanged: true
          },
          sampling: {}
        }
      )

      expect(client.protocol_version).to eq('2024-11-05')
    end

    it 'reports error when server returns unsupported protocol version' do
      mock_server_path = File.expand_path('../bin/simple_mock_server.rb', __dir__)

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
end
