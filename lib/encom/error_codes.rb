# frozen_string_literal: true

module Encom
  # Defines standard JSON-RPC error codes and MCP-specific error codes
  module ErrorCodes
    # Standard JSON-RPC error codes
    PARSE_ERROR = -32700
    INVALID_REQUEST = -32600
    METHOD_NOT_FOUND = -32601
    INVALID_PARAMS = -32602
    INTERNAL_ERROR = -32603
    
    # MCP specific error codes
    TOOL_EXECUTION_ERROR = -32000
    PROTOCOL_ERROR = -32001
  end
end 