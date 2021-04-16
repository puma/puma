# frozen_string_literal: true

require 'fiber'
require 'timeout'

module Puma
  class FiberPool
    SHUTDOWN_GRACE_TIME = 5

    def initialize(_min, _max, *extra, &block)
      @block = block
      @extra = extra.map { |i| i.new }

      @shutdown = false
      @out_of_band_pending = false
      @fibers = []

      @clean_thread_locals = false
    end

    def auto_reap!(*); end
    def auto_trim!(*); end

    def backlog; 0 end
    def spawned; 0 end
    def pool_capacity; 0 end

    attr_accessor :clean_thread_locals
    attr_accessor :out_of_band_hook # @version 5.0.0

    def self.clean_thread_locals
      Thread.current.keys.each do |key| # rubocop: disable Performance/HashEachMethods
        Thread.current[key] = nil unless key == :__recursive_key__
      end
    end

    # @!attribute [r] busy_threads
    # @version 5.0.0
    def busy_threads
      @fibers.length
    end

    # @version 5.0.0
    def trigger_out_of_band_hook
      return false unless out_of_band_hook && out_of_band_hook.any?

      # we execute on idle hook when all threads are free
      return false unless @fibers.empty?

      out_of_band_hook.each(&:call)
      true
    rescue Exception => e
      STDERR.puts "Exception calling out_of_band_hook: #{e.message} (#{e.class})"
      true
    end

    private :trigger_out_of_band_hook

    # Add +work+ for a Fiber to pickup and process.
    def <<(work)
      if @shutdown
        raise "Unable to add work while shutting down"
      end

      Fiber.schedule do
        begin
          @fibers << (fiber = Fiber.current)
          @out_of_band_pending = @block.call(work, *@extra)
          if @out_of_band_pending && trigger_out_of_band_hook
            @out_of_band_pending = false
          end
        ensure
          @fibers.delete fiber
          @waiting.resume if @waiting
        end
      end
    end

    def wait_until_not_full
    end

    # @version 5.0.0
    def wait_for_less_busy_worker(delay_s)
      return unless delay_s && delay_s > 0

      # Ruby MRI does GVL, this can result
      # in processing contention when multiple threads
      # (requests) are running concurrently
      return unless Puma.mri?

      return if @shutdown

      # do not delay, if we are not busy
      return unless busy_threads > 0

      # this will be signaled once a request finishes,
      # which can happen earlier than delay
      @waiting = Fiber.current
      sleep delay_s
      @waiting = nil
    end

    def shutdown(timeout=nil)
      @shutdown = true

      join = ->(inner_timeout) do
        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        @fibers.count(&:alive?).times do
          @waiting = Fiber.current
          if inner_timeout
            elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
            sleep inner_timeout - elapsed
          else
            sleep
          end
          @waiting = nil
        end
      end

      # Wait +timeout+ seconds for threads to finish.
      join.call(timeout) unless timeout == 0

      # If threads are still running, raise ForceShutdown and wait to finish.
      @fibers.dup.each {|f| f.raise ThreadPool::ForceShutdown if f.alive?}
      join.call(SHUTDOWN_GRACE_TIME)

      # If fibers are _still_ running, raise an error.
      raise "Error: #{@fibers.length} fibers still running:\n#{@fibers.map(&:backtrace).join("\n")}" if @fibers.any?(&:alive?)
    end

    def with_force_shutdown(&block)
      yield
    end
  end
end
