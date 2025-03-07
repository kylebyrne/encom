# frozen_string_literal: true

module Encom
  class Server
    class Tool
      attr_reader :name, :description, :schema

      # Initialize a new tool
      #
      # @param name [Symbol, String] The name of the tool
      # @param description [String] A description of what the tool does
      # @param schema [Hash] A hash describing the input schema for the tool
      # @param proc [Proc] A proc that implements the tool's functionality
      def initialize(name:, description:, schema:, proc:)
        @name = name
        @description = description
        @schema = schema
        @proc = proc
      end

      def definition
        {
          name: @name.to_s,
          description: @description,
          inputSchema: schema_definition
        }.compact
      end

      def call(arguments)
        result = nil
        
        begin
          if @proc.parameters.first && @proc.parameters.first[0] == :keyreq
            # If the proc expects keyword arguments, pass the arguments hash
            result = @proc.call(**arguments)
          else
            # Otherwise, pass arguments as an array
            result = @proc.call(*arguments)
          end
          
          # Ensure the result is in the standard format
          standardize_tool_response(result)
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
      end

      private

      # Standardize tool response to ensure it conforms to the MCP format
      # 
      # @param result [Hash, String, Array, Object] The raw result from the tool proc
      # @return [Hash] A standardized response hash with content array
      def standardize_tool_response(result)
        # If the result is already in the expected format (has content array), return it
        return result if result.is_a?(Hash) && result[:content].is_a?(Array)
        
        # If it's a hash with isError, leave it as is
        return result if result.is_a?(Hash) && result[:isError]
        
        # If it's a string, convert to text content
        if result.is_a?(String)
          return {
            content: [
              {
                type: 'text',
                text: result
              }
            ]
          }
        end
        
        # If it's an array, assume it's already a content array
        if result.is_a?(Array)
          return {
            content: result
          }
        end
        
        # For any other type, convert to string and wrap as text
        {
          content: [
            {
              type: 'text',
              text: result.to_s
            }
          ]
        }
      end

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
