# frozen_string_literal: true

require 'encom/server'

RSpec.describe Encom do
  before do
    stub_const('ExampleServer', Class.new(Encom::Server) do
      name 'example_server'
      version '1.0.0'

      tool :add, 'Add two numbers together', {
        a: {
          type: Integer
        },
        b: {
          type: Integer
        }
      }, ->(a, b) { a + b }
    end)
  end

  let(:server) { ExampleServer.new }

  describe '#name' do
    it 'lets you access the name' do
      expect(server.name).to eq 'example_server'
    end
  end

  describe '#version' do
    it 'lets you access the version' do
      expect(server.version).to eq '1.0.0'
    end
  end

  describe '#tools' do
    it 'returns the tools defined on the server' do
      expect(server.tools).to match_array [
        have_attributes(
          class: Encom::Server::Tool,
          name: :add,
          description: 'Add two numbers together'
        )
      ]
    end
  end

  describe '#call_tool' do
    it 'calls the tool with the arguments specified' do
      result = server.call_tool(:add, [3, 4])
      expect(result).to eq 7
    end
  end
end
