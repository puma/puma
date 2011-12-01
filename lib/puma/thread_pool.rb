require 'thread'

module Puma
  # A simple thread pool management object.
  #
  class ThreadPool

    # Maintain a minimum of +min+ and maximum of +max+ threads
    # in the pool.
    #
    # The block passed is the work that will be performed in each
    # thread.
    #
    def initialize(min, max, &blk)
      @todo = Queue.new
      @mutex = Mutex.new

      @spawned = 0
      @min = min
      @max = max
      @block = blk

      @trim_requested = 0

      @workers = []

      min.times { spawn_thread }
    end

    attr_reader :spawned

    # How many objects have yet to be processed by the pool?
    #
    def backlog
      @todo.size
    end

    Stop = Object.new
    Trim = Object.new

    # :nodoc:
    def spawn_thread
      @mutex.synchronize do
        @spawned += 1
      end

      th = Thread.new do
        todo = @todo
        block = @block

        while true
          work = todo.pop

          case work
          when Stop
            break
          when Trim
            @mutex.synchronize do
              @trim_requested -= 1
            end

            break
          else
            block.call work
          end
        end

        @mutex.synchronize do
          @spawned -= 1
          @workers.delete th
        end
      end

      @mutex.synchronize { @workers << th }

      th
    end

    # Add +work+ to the todo list for a Thread to pickup and process.
    def <<(work)
      if @todo.num_waiting == 0 and @spawned < @max
        spawn_thread
      end

      @todo << work
    end

    # If too many threads are in the pool, tell one to finish go ahead
    # and exit.
    #
    def trim
      @mutex.synchronize do
        if @spawned - @trim_requested > @min
          @trim_requested += 1
          @todo << Trim
        end
      end
    end

    # Tell all threads in the pool to exit and wait for them to finish.
    #
    def shutdown
      @spawned.times do
        @todo << Stop
      end

      @workers.each { |w| w.join }

      @spawned = 0
      @workers = []
    end
  end
end
