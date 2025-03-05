#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'encom/client'
require 'encom/transport/stdio'
require 'fileutils'
require 'tmpdir'

# Create a client with appropriate capabilities
def create_client
  client = Encom::Client.new(
    name: 'FilesystemDemoClient',
    version: '1.0.0',
    capabilities: {
      tools: {
        execute: true
      }
    }
  )

  # Set up error handling
  client.on_error do |error|
    puts "ERROR: #{error.class} - #{error.message}"
  end

  client
end

# Connect to the filesystem server
def connect_to_server(client)
  # Use npx to run the server without requiring global installation
  transport = Encom::Transport::Stdio.new(
    command: 'npx',
    args: [
      '-y',
      '@modelcontextprotocol/server-filesystem',
      '.' # Allow access to the current directory
    ]
  )

  puts 'Connecting to filesystem server using npx...'
  client.connect(transport)

  # Give it a moment to initialize
  sleep(1)

  if client.initialized
    puts "✓ Connected to #{client.server_info[:name]} #{client.server_info[:version]}"
    puts "✓ Protocol version: #{client.protocol_version}"
    puts "✓ Server capabilities: #{client.server_capabilities.inspect}"
    puts ''
  else
    puts '✗ Failed to connect to server'
    exit(1)
  end
end

# List available tools
def list_tools(client)
  puts 'Fetching available tools...'
  tools = client.list_tools

  puts "Available tools (#{tools.size}):"
  tools.each_with_index do |tool, i|
    puts "#{i + 1}. #{tool[:name]} - #{tool[:description]}"
  end
  puts ''

  tools
end

# Demo the filesystem tools
def demo_filesystem_tools(client, _tools)
  # Get the list of allowed directories
  puts 'Getting allowed directories...'
  result = client.call_tool(
    name: 'list_allowed_directories',
    arguments: {}
  )
  allowed_dirs = extract_text_content(result)
  puts allowed_dirs
  puts ''

  # List files in current directory
  puts 'Listing files in current directory...'
  result = client.call_tool(
    name: 'list_directory',
    arguments: {
      path: '.'
    }
  )
  puts extract_text_content(result)
  puts ''

  # Create a temporary file within the project directory
  temp_file = "examples/mcp_demo_#{Time.now.to_i}.txt"
  puts "Creating a temporary file at #{temp_file}..."

  content = "This is a test file created by the MCP filesystem demo at #{Time.now}"
  result = client.call_tool(
    name: 'write_file',
    arguments: {
      path: temp_file,
      content: content
    }
  )
  puts extract_text_content(result)
  puts ''

  # Read the file back
  puts 'Reading back the file content...'
  result = client.call_tool(
    name: 'read_file',
    arguments: {
      path: temp_file
    }
  )
  puts "File content: #{extract_text_content(result)}"
  puts ''

  # Get file info
  puts 'Getting file information...'
  result = client.call_tool(
    name: 'get_file_info',
    arguments: {
      path: temp_file
    }
  )
  puts extract_text_content(result)
  puts ''

  # Clean up - Move the file to a .bak extension to demonstrate move_file
  puts 'Demonstrating move_file by renaming the temporary file...'
  bak_file = "#{temp_file}.bak"
  result = client.call_tool(
    name: 'move_file',
    arguments: {
      source: temp_file,
      destination: bak_file
    }
  )
  puts extract_text_content(result)
  puts "File renamed to: #{bak_file}"
  puts ''

  # Search for our backup file
  puts 'Searching for our backup file...'
  result = client.call_tool(
    name: 'search_files',
    arguments: {
      path: 'examples',
      pattern: 'mcp_demo_'
    }
  )
  puts extract_text_content(result)
  puts ''

  puts "Note: Remember to manually delete the backup file: #{bak_file}"
  puts ''
end

# Helper to extract text content from a tool response
def extract_text_content(result)
  if result && result[:content]&.first
    content_item = result[:content].first
    if content_item[:type] == 'text'
      content_item[:text]
    else
      content_item.inspect
    end
  else
    'No content in response'
  end
end

# Main program
def main
  client = create_client
  connect_to_server(client)

  tools = list_tools(client)
  demo_filesystem_tools(client, tools)

  puts 'Demo completed successfully!'
ensure
  client&.close
end

# Run the demo
main if $PROGRAM_NAME == __FILE__
