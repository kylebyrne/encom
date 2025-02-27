require 'open3'
require 'timeout'
require 'json'

module Encom
  module Transport
    class Stdio
      attr_reader :process_pid

      def initialize(
        command:,
        args: []
      )
        @command = command
        @args = args
        @process = nil
        @read_buffer = ''
        @callbacks = {
          error: [],
          close: [],
          data: []
        }
        @mutex = Mutex.new
        @json_buffer = '' # Buffer for accumulating JSON messages
      end

      # Register event handlers
      def on_error(&block)
        @callbacks[:error] << block
        self
      end

      def on_close(&block)
        @callbacks[:close] << block
        self
      end

      def on_data(&block)
        @callbacks[:data] << block
        self
      end

      def start
        raise 'StdioClientTransport already started!' if @process

        env = ENV.to_h

        command = @command
        args = @args

        @stdin, @stdout, @stderr, @process = Open3.popen3(
          env,
          command,
          *args
          # chdir: @server_params[:cwd]
        )

        @process_pid = @process.pid

        start_stdout_thread
        start_stderr_thread
        start_process_monitor_thread

        self
      end

      def send(data)
        return false unless @process && @stdin

        data = "#{data}\n" unless data.end_with?("\n")

        begin
          @stdin.write(data)
          @stdin.flush
          true
        rescue IOError, Errno::EPIPE => e
          trigger_error(e)
          false
        end
      end

      def send_line(data)
        send("#{data}\n")
      end

      def close
        return unless @process

        begin
          @stdin.close
        rescue StandardError
          nil
        end

        begin
          Timeout.timeout(2) do
            Process.wait(@process.pid)
          rescue StandardError
            nil
          end
        rescue Timeout::Error
          begin
            Process.kill('TERM', @process.pid)
          rescue StandardError
            nil
          end

          begin
            Timeout.timeout(1) do
              Process.wait(@process.pid)
            rescue StandardError
              nil
            end
          rescue Timeout::Error
            begin
              Process.kill('KILL', @process.pid)
            rescue StandardError
              nil
            end
          end
        end

        # Clean up resources
        begin
          @stdout.close
        rescue StandardError
          nil
        end
        begin
          @stderr.close
        rescue StandardError
          nil
        end

        trigger_close

        @process = nil
      end

      private

      def start_stdout_thread
        Thread.new do
          while true
            begin
              chunk = @stdout.read_nonblock(1024)
              if chunk && !chunk.empty?
                @mutex.synchronize do
                  @read_buffer << chunk
                end
                process_read_buffer
              end
            rescue IO::WaitReadable
              IO.select([@stdout], nil, nil, 0.1)
              retry
            rescue EOFError
              break
            end
          end
        rescue IOError, Errno::EPIPE => e
          trigger_error(e) unless @process.nil?
        ensure
          trigger_close if @process && !@stdout.closed?
        end
      end

      def start_stderr_thread
        Thread.new do
          while line = @stderr.gets
            trigger_error(RuntimeError.new("Process stderr: #{line.strip}"))
          end
        rescue IOError, Errno::EPIPE => e
          trigger_error(e) unless @process.nil?
        end
      end

      def start_process_monitor_thread
        Thread.new do
          Process.wait(@process.pid)
          exit_status = $?.exitstatus
          trigger_close(exit_status)
        rescue Errno::ECHILD, Errno::ESRCH
          trigger_close
        end
      end

      def process_read_buffer
        data = nil

        @mutex.synchronize do
          data = @read_buffer.dup
          @read_buffer.clear
        end

        return unless data && !data.empty?

        @json_buffer += data

        process_json_messages
      end

      def process_json_messages
        while @json_buffer.include?("\n")
          message, remainder = @json_buffer.split("\n", 2)

          if message && !message.empty?
            begin
              JSON.parse(message)

              trigger_data(message)
            rescue JSON::ParserError
              @json_buffer = message + "\n" + (remainder || '')
              return
            end
          end

          @json_buffer = remainder || ''
        end
      end

      def trigger_error(error)
        @callbacks[:error].each { |callback| callback.call(error) }
      end

      def trigger_close(exit_status = nil)
        @callbacks[:close].each { |callback| callback.call(exit_status) }
      end

      def trigger_data(data)
        @callbacks[:data].each { |callback| callback.call(data) }
      end
    end
  end
end
