# frozen_string_literal: true

require 'encom/transport/stdio'
require 'json'

RSpec.describe Encom do
  it 'allows callbacks on close' do
    transport = Encom::Transport::Stdio.new(
      command: '/usr/bin/tee'
    )

    exited = false
    transport
      .on_close do |_data|
        exited = true
      end
      .start

    expect(exited).to be false
    transport.close
    expect(exited).to be true
  end

  it 'reads messages' do
    transport = Encom::Transport::Stdio.new(
      command: '/usr/bin/tee'
    )

    messages = []

    transport
      .on_data do |data|
        messages << JSON.parse(data, symbolize_names: true)
      end
      .start

    transport.send(
      JSON.generate(
        {
          jsonrpc: '2.0',
          id: 1,
          method: 'ping'
        }
      )
    )

    sleep(0.1)

    transport.close

    expect(messages).to eq(
      [
        {
          jsonrpc: '2.0',
          id: 1,
          method: 'ping'
        }
      ]
    )
  end
end
