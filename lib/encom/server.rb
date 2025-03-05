require 'encom/server/tool'

module Encom
  class Server
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
      tools.find { _1.name == name.to_sym }.call(arguments)
    end
  end
end
