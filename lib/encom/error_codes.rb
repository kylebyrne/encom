# frozen_string_literal: true

module Encom
  # Defines standard JSON-RPC error codes and MCP-specific error codes
  module ErrorCodes
    # Standard JSON-RPC error codes
    PARSE_ERROR = -32_700
    INVALID_REQUEST = -32_600
    METHOD_NOT_FOUND = -32_601
    INVALID_PARAMS = -32_602
    INTERNAL_ERROR = -32_603

    # MCP specific error codes
    TOOL_EXECUTION_ERROR = -32_000
    PROTOCOL_ERROR = -32_001
  end
end
