# frozen_string_literal: true

module Encom
  class Server
    class Tool
      CallError = Class.new(StandardError)

      attr_reader :name, :description

      def initialize(name:, description:, schema:, proc:)
        @name = name
        @schema = schema
        @proc = proc
        @description = description
      end

      def definition
        {
          name: @name.to_s,
          description: @description,
          inputSchema: schema_definition
        }.compact
      end

      def call(arguments)
        if @proc.parameters.first && @proc.parameters.first[0] == :keyreq
          # If the proc expects keyword arguments, pass the arguments hash
          @proc.call(**arguments)
        else
          # Otherwise, pass arguments as an array
          @proc.call(*arguments)
        end
      rescue StandardError => e
        # Return error in MCP-compliant format as per docs
        {
          isError: true,
          content: [
            {
              type: 'text',
              text: "Error: #{e.message}"
            }
          ]
        }
      end

      private

      def schema_definition
        properties = {}
        required = []

        @schema.each do |key, value|
          properties[key] = if value.is_a?(Hash)
                              {
                                type: ruby_type_to_json_type(value[:type]),
                                description: value[:description]
                              }.compact
                            else
                              {
                                type: ruby_type_to_json_type(value)
                              }.compact
                            end
        end

        @proc.parameters.each do |param_type, param_name|
          required << param_name.to_s if param_type == :keyreq
        end

        {
          type: 'object',
          properties: properties,
          required: required
        }
      end

      def ruby_type_to_json_type(type)
        return nil unless type

        case type.to_s
        when 'Integer'
          'number'
        when 'String'
          'string'
        when 'TrueClass', 'FalseClass', 'Boolean'
          'boolean'
        when 'Float'
          'number'
        when 'Array'
          'array'
        when 'Hash'
          'object'
        else
          type.to_s.downcase
        end
      end
    end
  end
end
