# Encom

Work in progress Ruby implementation of the [Model Context Protocol](https://modelcontextprotocol.io/introduction) (MCP).

Encom is a Ruby library for implementing both MCP servers and clients. The gem provides a flexible and easy-to-use framework to build applications that can communicate using the [MCP specification](https://spec.modelcontextprotocol.io/specification/2024-11-05/).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'encom'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install encom
```

## Building an MCP Server

### Basic Server Implementation

```ruby
require 'encom/server'
require 'encom/server_transport/stdio'

class MyServer < Encom::Server
  name "MyMCPServer"
  version "1.0.0"
  
  # Define a tool that the server exposes
  tool :hello_world,
       "Says hello to the specified name",
       {
         type: "object",
         properties: {
           name: {
             type: "string",
             description: "The name to greet"
           }
         },
         required: ["name"]
       } do |args|
         { greeting: "Hello, #{args[:name]}!" }
       end
end

# Start the server with a chosen transport mechanism
server = MyServer.new
server.run(Encom::ServerTransport::Stdio)
```

### Starting Your Server

```ruby
# Run the server file
ruby my_server.rb
```

## Building an MCP Client

### Basic Client Implementation

```ruby
require 'encom/client'
require 'encom/transport/stdio'

# Create a client
client = Encom::Client.new(
  name: 'MyClient',
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

# Connect to an MCP server
transport = Encom::Transport::Stdio.new(
  command: 'ruby',
  args: ['path/to/your/server.rb']
)

client.connect(transport)

# List available tools
tools = client.list_tools

# Call a tool
result = client.call_tool(
  name: 'hello_world',
  arguments: { name: 'World' }
)

puts result[:greeting] # Outputs: Hello, World!

# Close the connection when done
client.close
```

## Example Usage

See the `examples` directory for complete demonstrations:

- `filesystem_demo.rb`: Shows how to connect to an MCP filesystem server

## Specification support

### Server

- Tools ✅
- Prompts 🟠
- Resources 🟠

We haven't yet added a DSL for defining prompts or resources but these can be defined as shown in `bin/mock_mcp_server`

### Client
- Server tool interface ✅
- Server prompt interface ❌
- Server resource interface ❌
- Roots ❌
- Sampling ❌


### Available Transports

Encom currently supports different transport mechanisms for communication:

- **STDIO**: Communication through standard input/output
- Custom transports can be implemented by extending the base transport classes

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).


## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/kylebyrne/encom.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
