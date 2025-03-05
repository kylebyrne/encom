# frozen_string_literal: true

require 'encom/server/tool'

RSpec.describe Encom::Server::Tool do
  describe '#definition' do
    it 'returns a correctly formatted tool definition' do
      tool = Encom::Server::Tool.new(
        name: :add,
        description: 'Add two numbers together and optionally multiply the result',
        schema: {
          a: {
            type: Integer,
            description: 'The first number'
          },
          b: Integer,
          c: Integer
        },
        proc: lambda { |a:, b:, c: 1|
          (a + b) * c
        }
      )

      expect(tool.definition).to eq(
        {
          name: 'add',
          description: 'Add two numbers together and optionally multiply the result',
          inputSchema: {
            type: 'object',
            properties: {
              a: {
                type: 'number',
                description: 'The first number'
              },
              b: {
                type: 'number'
              },
              c: {
                type: 'number'
              }
            },
            required: %w[a b]
          }
        }
      )
    end
  end
end
