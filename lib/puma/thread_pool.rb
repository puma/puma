require 'thread'

module Puma
  class ThreadPool
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

    def backlog
      @todo.size
    end

    Stop = Object.new
    Trim = Object.new

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

    def <<(work)
      if @todo.num_waiting == 0 and @spawned < @max
        spawn_thread
      end

      @todo << work
    end

    def trim
      @mutex.synchronize do
        if @spawned - @trim_requested > @min
          @trim_requested += 1
          @todo << Trim
        end
      end
    end

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
