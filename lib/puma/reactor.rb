module Puma
  class Reactor
    DefaultSleepFor = 5

    def initialize(server, app_pool)
      @server = server
      @events = server.events
      @app_pool = app_pool

      @mutex = Mutex.new
      @ready, @trigger = IO.pipe
      @input = []
      @sleep_for = DefaultSleepFor
      @timeouts = []

      @sockets = [@ready]
    end

    def run
      sockets = @sockets

      while true
        ready = IO.select sockets, nil, nil, @sleep_for

        if ready and reads = ready[0]
          reads.each do |c|
            if c == @ready
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
              if c.timeout_at
                @timeouts.delete c
              end

              begin
                if c.try_to_finish
                  @app_pool << c
                  sockets.delete c
                end

              # The client doesn't know HTTP well
              rescue HttpParserError => e
                c.close
                sockets.delete c

                @events.parse_error @server, c.env, e

              rescue StandardError => e
                c.close
                sockets.delete c
              end
            end
          end
        end

        unless @timeouts.empty?
          now = Time.now

          while @timeouts.first.timeout_at < now
            c = @timeouts.shift
            sockets.delete c
            c.close

            break if @timeouts.empty?
          end

          calculate_sleep
        end
      end
    end

    def run_in_thread
      @thread = Thread.new {
        while true
          begin
            run
            break
          rescue StandardError => e
            STDERR.puts "Error in reactor loop escaped: #{e.message} (#{e.class})"
            puts e.backtrace
          end
        end
      }
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
      @trigger << "c"
    end

    def shutdown
      @trigger << "!"
      @thread.join
    end
  end
end
