require "open3"
require 'timeout'

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

      # Start the process and set up I/O handling
      def start
        raise "StdioClientTransport already started!" if @process

        # Set up default environment or use provided one
        # env = @server_params[:env] || ENV.to_h
        env = ENV.to_h

        # Prepare command and arguments
        command = @command
        args = @args

        # Start the process with Open3
        @stdin, @stdout, @stderr, @process = Open3.popen3(
          env,
          command,
          *args
          # chdir: @server_params[:cwd]
        )

        @process_pid = @process.pid

        # Start background threads to handle IO
        start_stdout_thread
        start_stderr_thread
        start_process_monitor_thread

        # Return self for method chaining
        self
      end

      # Send data to the process
      def send(data)
        return false unless @process && @stdin

        begin
          @stdin.write(data)
          @stdin.flush
          true
        rescue IOError, Errno::EPIPE => e
          trigger_error(e)
          false
        end
      end

      # Send a line of data (with newline)
      def send_line(data)
        send("#{data}\n")
      end

      # Close the process
      def close
        return unless @process

        # Close stdin to signal we're done writing
        @stdin.close rescue nil

        # Give the process a chance to exit gracefully
        begin
          Timeout.timeout(2) do
            Process.wait(@process.pid) rescue nil
          end
        rescue Timeout::Error
          # If it doesn't exit in time, terminate it
          Process.kill('TERM', @process.pid) rescue nil

          # Give it a bit more time
          begin
            Timeout.timeout(1) do
              Process.wait(@process.pid) rescue nil
            end
          rescue Timeout::Error
            # If it still doesn't exit, force kill it
            Process.kill('KILL', @process.pid) rescue nil
          end
        end

        # Clean up resources
        @stdout.close rescue nil
        @stderr.close rescue nil

        # Notify of closure
        trigger_close

        @process = nil
      end

      private

      def start_stdout_thread
        Thread.new do
          begin
            # Use read_nonblock for more responsive reading
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
                # Nothing to read yet, sleep briefly then try again
                IO.select([@stdout], nil, nil, 0.1)
                retry
              rescue EOFError
                # End of file reached, normal exit
                break
              end
            end
          rescue IOError, Errno::EPIPE => e
            trigger_error(e) unless @process.nil?
          ensure
            trigger_close if @process && !@stdout.closed?
          end
        end
      end

      def start_stderr_thread
        Thread.new do
          begin
            while line = @stderr.gets
              trigger_error(RuntimeError.new("Process stderr: #{line.strip}"))
            end
          rescue IOError, Errno::EPIPE => e
            trigger_error(e) unless @process.nil?
          end
        end
      end

      def start_process_monitor_thread
        Thread.new do
          begin
            Process.wait(@process.pid)
            exit_status = $?.exitstatus
            trigger_close(exit_status)
          rescue Errno::ECHILD, Errno::ESRCH => e
            # Process already gone
            trigger_close
          end
        end
      end

      def process_read_buffer
        # This is a simplified version - you might want to implement
        # more sophisticated buffer processing logic here
        data = nil

        @mutex.synchronize do
          data = @read_buffer.dup
          @read_buffer.clear
        end

        trigger_data(data) if data && !data.empty?
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
