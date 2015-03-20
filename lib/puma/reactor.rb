require 'puma/util'

module Puma
  class Reactor
    DefaultSleepFor = 5

    def initialize(server, app_pool)
      @server = server
      @events = server.events
      @app_pool = app_pool

      @mutex = Mutex.new
      @ready, @trigger = Puma::Util.pipe
      @input = []
      @sleep_for = DefaultSleepFor
      @timeouts = []

      @sockets = [@ready]
    end

    private

    def run_internal
      sockets = @sockets

      while true
        begin
          ready = IO.select sockets.map(&:to_io), nil, nil, @sleep_for
        rescue IOError => e
          if sockets.any? { |socket| socket.closed? }
            STDERR.puts "Error in select: #{e.message} (#{e.class})"
            STDERR.puts e.backtrace
            sockets = sockets.reject { |socket| socket.closed? }
            retry
          else
            raise
          end
        end

        if ready and reads = ready[0]
          reads.each do |c|
            client = sockets.detect{|socket| socket.to_io == c }
            if client == @ready
              @mutex.synchronize do
                case @ready.read(1)
                when "*"
                  sockets += @input
                  @input.clear
                when "c"
                  sockets.delete_if do |s|
                    if s == @ready
                      false
                    else
                      s.close
                      true
                    end
                  end
                when "!"
                  return
                end
              end
            else
              # We have to be sure to remove it from the timeout
              # list or we'll accidentally close the socket when
              # it's in use!
              if client.timeout_at
                @mutex.synchronize do
                  @timeouts.delete client
                end
              end

              begin
                if client.try_to_finish
                  @app_pool << client
                  sockets.delete client
                end

              # The client doesn't know HTTP well
              rescue HttpParserError => e
                client.write_400
                client.close

                sockets.delete client

                @events.parse_error @server, client.env, e
              rescue StandardError => e
                client.write_500
                client.close

                sockets.delete client
              end
            end
          end
        end

        unless @timeouts.empty?
          @mutex.synchronize do
            now = Time.now

            while @timeouts.first.timeout_at < now
              c = @timeouts.shift
              c.write_408 if c.in_data_phase
              c.close
              sockets.delete c

              break if @timeouts.empty?
            end

            calculate_sleep
          end
        end
      end
    end

    public

    def run
      run_internal
    ensure
      @trigger.close
      @ready.close
    end

    def run_in_thread
      @thread = Thread.new do
        begin
          run_internal
        rescue StandardError => e
          STDERR.puts "Error in reactor loop escaped: #{e.message} (#{e.class})"
          STDERR.puts e.backtrace
          retry
        ensure
          @trigger.close
          @ready.close
        end
      end
    end

    def calculate_sleep
      if @timeouts.empty?
        @sleep_for = DefaultSleepFor
      else
        diff = @timeouts.first.timeout_at.to_f - Time.now.to_f

        if diff < 0.0
          @sleep_for = 0
        else
          @sleep_for = diff
        end
      end
    end

    def add(c)
      @mutex.synchronize do
        @input << c
        @trigger << "*"

        if c.timeout_at
          @timeouts << c
          @timeouts.sort! { |a,b| a.timeout_at <=> b.timeout_at }

          calculate_sleep
        end
      end
    end

    # Close all watched sockets and clear them from being watched
    def clear!
      begin
        @trigger << "c"
      rescue IOError
      end
    end

    def shutdown
      begin
        @trigger << "!"
      rescue IOError
      end

      @thread.join
    end
  end
end
