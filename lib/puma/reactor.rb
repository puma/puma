# frozen_string_literal: true

require 'puma/util'
require 'puma/minissl'

module Puma
  # Internal Docs, Not a public interface.
  #
  # The Reactor object is responsible for ensuring that a request has been
  # completely received before it starts to be processed. This may be known as read buffering.
  # If read buffering is not done, and no other read buffering is performed (such as by an application server
  # such as nginx) then the application would be subject to a slow client attack.
  #
  # Each Puma "worker" process has its own Reactor. For example if you start puma with `$ puma -w 5` then
  # it will have 5 workers and each worker will have it's own reactor.
  #
  # For a graphical representation of how the reactor works see [architecture.md](https://github.com/puma/puma/blob/master/docs/architecture.md#connection-pipeline).
  #
  # ## Reactor Flow
  #
  # A request comes into a `Puma::Server` instance, it is then passed to a `Puma::Reactor` instance.
  # The reactor stores the request in an array and calls `IO.select` on the array in a loop.
  #
  # When the request is written to by the client then the `IO.select` will "wake up" and
  # return the references to any objects that caused it to "wake". The reactor
  # then loops through each of these request objects, and sees if they're  complete. If they
  # have a full header and body then the reactor passes the request to a thread pool.
  # Once in a thread pool, a "worker thread" can run the the application's Ruby code against the request.
  #
  # If the request is not complete, then it stays in the array, and the next time any
  # data is written to that socket reference, then the loop is woken up and it is checked for completeness again.
  #
  # A detailed example is given in the docs for `run_internal` which is where the bulk
  # of this logic lives.
  class Reactor
    DefaultSleepFor = 5

    # Creates an instance of Puma::Reactor
    #
    # The `server` argument is an instance of `Puma::Server`
    # this is used to write a response for "low level errors"
    # when there is an exception inside of the reactor.
    #
    # The `app_pool` is an instance of `Puma::ThreadPool`.
    # Once a request is fully formed (header and body are received)
    # it will be passed to the `app_pool`.
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
    # connected to `@trigger` object. When `@trigger` is written to, then the loop
    # will break on `IO.select` and return an array.
    #
    # ## When a request is added:
    #
    # When the `add` method is called, an instance of `Puma::Client` is added to the `@input` array.
    # Next the `@ready` pipe is "woken" by writing a string of `"*"` to `@trigger`.
    #
    # When that happens, the internal loop stops blocking at `IO.select` and returns a reference
    # to whatever "woke" it up. On the very first loop, the only thing in `sockets` is `@ready`.
    # When `@trigger` is written-to, the loop "wakes" and the `ready`
    # variable returns an array of arrays that looks like `[[#<IO:fd 10>], [], []]` where the
    # first IO object is the `@ready` object. This first array `[#<IO:fd 10>]`
    # is saved as a `reads` variable.
    #
    # The `reads` variable is iterated through. In the case that the object
    # is the same as the `@ready` input pipe, then we know that there was a `trigger` event.
    #
    # If there was a trigger event, then one byte of `@ready` is read into memory. In the case of the first request,
    # the reactor sees that it's a `"*"` value and the reactor adds the contents of `@input` into the `sockets` array.
    # The while then loop continues to iterate again, but now the `sockets` array contains a `Puma::Client` instance in addition
    # to the `@ready` IO object. For example: `[#<IO:fd 10>, #<Puma::Client:0x3fdc1103bee8 @ready=false>]`.
    #
    # Since the `Puma::Client` in this example has data that has not been read yet,
    # the `IO.select` is immediately able to "wake" and read from the `Puma::Client`. At this point the
    # `ready` output looks like this: `[[#<Puma::Client:0x3fdc1103bee8 @ready=false>], [], []]`.
    #
    # Each element in the first entry is iterated over. The `Puma::Client` object is not
    # the `@ready` pipe, so the reactor checks to see if it has the fully header and body with
    # the `Puma::Client#try_to_finish` method. If the full request has been sent,
    # then the request is passed off to the `@app_pool` thread pool so that a "worker thread"
    # can pick up the request and begin to execute application logic. This is done
    # via `@app_pool << c`. The `Puma::Client` is then removed from the `sockets` array.
    #
    # If the request body is not present then nothing will happen, and the loop will iterate
    # again. When the client sends more data to the socket the `Puma::Client` object will
    # wake up the `IO.select` and it can again be checked to see if it's ready to be
    # passed to the thread pool.
    #
    # ## Time Out Case
    #
    # In addition to being woken via a write to one of the sockets the `IO.select` will
    # periodically "time out" of the sleep. One of the functions of this is to check for
    # any requests that have "timed out". At the end of the loop it's checked to see if
    # the first element in the `@timeout` array has exceed it's allowed time. If so,
    # the client object is removed from the timeout aray, a 408 response is written.
    # Then it's connection is closed, and the object is removed from the `sockets` array
    # that watches for new data.
    #
    # This behavior loops until all the objects that have timed out have been removed.
    #
    # Once all the timeouts have been processed, the next duration of the `IO.select` sleep
    # will be set to be equal to the amount of time it will take for the next timeout to occur.
    # This calculation happens in `calculate_sleep`.
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

    # The `calculate_sleep` sets the value that the `IO.select` will
    # sleep for in the main reactor loop when no sockets are being written to.
    #
    # The values kept in `@timeouts` are sorted so that the first timeout
    # comes first in the array. When there are no timeouts the default timeout is used.
    #
    # Otherwise a sleep value is set that is the same as the amount of time it
    # would take for the first element to time out.
    #
    # If that value is in the past, then a sleep value of zero is used.
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

    # This method adds a connection to the reactor
    #
    # Typically called by `Puma::Server` the value passed in
    # is usually a `Puma::Client` object that responds like an IO
    # object.
    #
    # The main body of the reactor loop is in `run_internal` and it
    # will sleep on `IO.select`. When a new connection is added to the
    # reactor it cannot be added directly to the `sockets` aray, because
    # the `IO.select` will not be watching for it yet.
    #
    # Instead what needs to happen is that `IO.select` needs to be woken up,
    # the contents of `@input` added to the `sockets` array, and then
    # another call to `IO.select` needs to happen. Since the `Puma::Client`
    # object can be read immediately, it does not block, but instead returns
    # right away.
    #
    # This behavior is accomplished by writing to `@trigger` which wakes up
    # the `IO.select` and then there is logic to detect the value of `*`,
    # pull the contents from `@input` and add them to the sockets array.
    #
    # If the object passed in has a timeout value in `timeout_at` then
    # it is added to a `@timeouts` array. This array is then re-arranged
    # so that the first element to timeout will be at the front of the
    # array. Then a value to sleep for is derived in the call to `calculate_sleep`
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
