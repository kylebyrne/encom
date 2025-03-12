#!/usr/bin/env ruby
# frozen_string_literal: true

# A simple demonstration of connecting to the Git MCP server

require 'bundler/setup'
require 'encom/client'
require 'encom/transport/stdio'
require 'optparse'

# Parse command line arguments
options = {
  debug: false,
  timeout: 10
}

parser = OptionParser.new do |opts|
  opts.banner = "Usage: git_demo.rb [options]"
  
  opts.on("--debug", "Enable debug mode") do
    options[:debug] = true
  end
  
  opts.on("--timeout=SECONDS", Integer, "Set request timeout in seconds (default: 10)") do |t|
    options[:timeout] = t
  end
end

parser.parse!

# Use the current working directory as the repository
repository_path = Dir.pwd

puts "Git MCP Server Demo"
puts "----------------"
puts "Repository path: #{repository_path}"
puts "Debug mode: #{options[:debug]}"
puts ""

# Create a client
client = Encom::Client.new(
  name: 'GitDemoClient',
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
  puts error.backtrace.join("\n") if error.respond_to?(:backtrace)
end

# Set up the transport with UVX
transport = Encom::Transport::Stdio.new(
  command: 'uvx',
  args: ['mcp-server-git', '--repository', repository_path],
  debug_mode: options[:debug]
)

# Connect to the Git server
puts "Connecting to Git server..."
client.connect(transport)

# Wait for initialization to complete
start_time = Time.now
timeout = options[:timeout]
while !client.initialized && Time.now - start_time < timeout
  sleep(0.1)
end

unless client.initialized
  puts "Failed to initialize connection within #{timeout} seconds"
  exit 1
end

puts "✓ Connected to #{client.server_info[:name]} #{client.server_info[:version]}"
puts "✓ Protocol version: #{client.protocol_version}"

# List available tools
puts "\n📋 Available tools:"
begin
  tools = client.list_tools
  
  if tools.nil? || tools.empty?
    puts "No tools available or failed to list tools"
    tools = []
  else
    tools.each do |tool|
      puts "- #{tool[:name]}: #{tool[:description]}"
    end
  end
rescue => e
  puts "Error listing tools: #{e.message}"
  tools = []
end

# Call git_status tool if available
tools_by_name = (tools || []).each_with_object({}) { |tool, hash| hash[tool[:name]] = tool }

if tools_by_name['git_status']
  puts "\n🔍 Checking Git status..."
  begin
    result = client.call_tool(
      name: 'git_status',
      arguments: { repo_path: repository_path }
    )
    
    if result&.dig(:content)
      # Extract text content from the response
      text_items = result[:content].select { |item| item[:type] == 'text' }
      puts text_items.map { |item| item[:text] }.join("\n")
    else
      puts "No content in response: #{result.inspect}"
    end
  rescue => e
    puts "Error calling git_status: #{e.message}"
  end
end

# Close the connection
puts "\nClosing connection..."
client.close 