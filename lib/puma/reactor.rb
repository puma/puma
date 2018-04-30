require 'puma/util'
require 'puma/minissl'

module Puma
  # Internal Docs, Not a public interface.
  #
  # The Reactor object is responsible for ensuring that a request has been
  # completely received before it starts to be processed. This may be known as read buffering.
  # If this is not done and no other read buffering is performed (such as by an application) server
  # such as nginx then the application would be subject to a slow client attack.
  #
  # For a graphical representation see [architecture.md](https://github.com/puma/puma/blob/master/docs/architecture.md#connection-pipeline).
  #
  # A request comes into a `Puma::Server`, it is then passed to the reactor.
  # The reactor stores the request in an array and calls `IO.select` on the array in a loop.
  # When the request is written to by the client then the `IO.select` will "wake up" and
  # return the references to any objects that caused it to "wake". The reactor
  # then loops through each of these request objects, sees if they're  complete. If they
  # are complete (have a full header and body) then it passes the request to a thread pool
  # where a "worker thread" can run the the application's Ruby code against the request.
  #
  # If the request is not complete then it stays in the array and the next time any
  # data is written to it the loop is woken up and it is checked for completeness again.
  #
  # A detailed example is given in the docs for `run_internal` which is where the bulk
  # of this logic lives.
  class Reactor
    DefaultSleepFor = 5

    def initialize(server, app_pool)
      @server = server
      @events = server.events
      @app_pool = app_pool

      @mutex = Mutex.new

      # Read / Write pipes to wake up internal while loop
      @ready, @trigger = Puma::Util.pipe
      @input = []
      @sleep_for = DefaultSleepFor
      @timeouts = []

      @sockets = [@ready]
    end

    private


    # Until a request is added via the `add` method this method will internally
    # loop, waiting on the `sockets` array objects. The only object in this
    # array at first is the `@ready` IO object, which is the read end of a pipe
    # connected to `@trigger`. When `@trigger` is written to, then the loop
    # will break on IO.select and return an array.
    #
    # ## When a request is added:
    #
    # When the `add` method is called, an instance of `Puma::Client` is added to the `@input` array.
    # Next the `@ready` pipe is "woken" by writing a string of `"*"` to `@trigger`.
    #
    # When that happens the internal while loop stops blocking and returns a reference
    # to whatever "woke" it up. On the very first loop the only thing in `sockets` is `@ready`.
    # When `@trigger` is written to the loop "wakes" and the `ready`
    # variable returns an array of arrays like `[[#<IO:fd 10>], [], []]` where the
    # first IO object is the `@ready` object. This first array `[#<IO:fd 10>]`
    # is saved as a `reads` array.
    #
    # The `reads` array is iterated through and read. In the case that the object
    # is the same as the `@ready` input pipe, then we know that there was a `trigger` event.
    #
    #
    # If there was a trigger event then one byte of `@ready` is read into memory. In this case of the first request
    # it sees that it's a `"*"` and it adds the contents of `@input` into the `sockets` array.
    # The while loop continues to iterate again, but now the `sockets` array contains a `Puma::Client` instance in addition
    # to the `@ready` IO object. For example: `[#<IO:fd 10>, #<Puma::Client:0x3fdc1103bee8 @ready=false>]`.
    #
    # Since the `Puma::Client` in this example has data that has not been read yet,
    # the IO.select is immediately able to "wake" and read from the `Puma::Client`. At this point the
    # `ready` output looks like this: `[[#<Puma::Client:0x3fdc1103bee8 @ready=false>], [], []]`.
    #
    # Each element in the first entry is iterated over. The `Puma::Client` object is not
    # the `@ready` pipe so we check to see if we have the body, or only the header via
    # the `Puma::Client#try_to_finish` method. If the full request has been sent,
    # then it is passed off to the `@app_pool` thread pool so that a  "worker thread"
    # can pick up the request and begin to run application logic. This is done
    # via `@app_pool << c`. The `Puma::Client` is then removed from the `sockets` array.
    #
    # If the request body is not present then nothing will happen, and the loop will iterate
    # again. When the client sends more data to the socket the `Puma::Client` object will
    # wake up the `IO.select` and it can again be checked to see if it's ready to be
    # passed to the thread pool.
    #
    # There is some timeout logic as well
    def run_internal
      sockets = @sockets

      while true
        begin
          ready = IO.select sockets, nil, nil, @sleep_for
        rescue IOError => e
          Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
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
                @mutex.synchronize do
                  @timeouts.delete c
                end
              end

              begin
                if c.try_to_finish
                  @app_pool << c
                  sockets.delete c
                end

              # Don't report these to the lowlevel_error handler, otherwise
              # will be flooding them with errors when persistent connections
              # are closed.
              rescue ConnectionError
                c.write_500
                c.close

                sockets.delete c

              # SSL handshake failure
              rescue MiniSSL::SSLError => e
                @server.lowlevel_error(e, c.env)

                ssl_socket = c.io
                addr = ssl_socket.peeraddr.last
                cert = ssl_socket.peercert

                c.close
                sockets.delete c

                @events.ssl_error @server, addr, cert, e

              # The client doesn't know HTTP well
              rescue HttpParserError => e
                @server.lowlevel_error(e, c.env)

                c.write_400
                c.close

                sockets.delete c

                @events.parse_error @server, c.env, e
              rescue StandardError => e
                @server.lowlevel_error(e, c.env)

                c.write_500
                c.close

                sockets.delete c
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
        Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
      end
    end

    def shutdown
      begin
        @trigger << "!"
      rescue IOError
        Thread.current.purge_interrupt_queue if Thread.current.respond_to? :purge_interrupt_queue
      end

      @thread.join
    end
  end
end
