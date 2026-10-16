# frozen_string_literal: true

module Puma
  class UnsupportedBackend < StandardError; end

  # Monitors a collection of IO objects, calling a block whenever
  # any monitored object either receives data or times out, or when the Reactor shuts down.
  #
  # The waiting/wake up is performed with nio4r, which will use the appropriate backend (libev,
  # Java NIO or just plain IO#select). The call to `NIO::Selector#select` will
  # 'wakeup' any IO object that receives data.
  #
  # This class additionally tracks a timeout for every added object,
  # and wakes up any object when its timeout elapses.
  #
  # The implementation uses a Queue to synchronize adding new objects from the internal select loop.
  class Reactor

    # @!attribute [rw] reactor_max
    #   Maximum number of clients in the selector.  Reset with calls to `Server.stats`.
    attr_accessor :reactor_max
    attr_reader :reactor_size

    # Create a new Reactor to monitor IO objects added by #add.
    # The provided block will be invoked when an IO has data available to read,
    # its timeout elapses, or when the Reactor shuts down.
    def initialize(backend, &block)
      require 'nio'
      valid_backends = [:auto, *::NIO::Selector.backends]
      unless valid_backends.include?(backend)
        raise ArgumentError.new("unsupported IO selector backend: #{backend} (available backends: #{valid_backends.join(', ')})")
      end

      @selector = ::NIO::Selector.new(NIO::Selector.backends.delete(backend))
      @input = Queue.new
      @timeouts = {}
      @early_timeouts = {}
      @earliest = nil
      @early_earliest = nil
      @last_timeout_at = 0.0
      @early_last_timeout_at = 0.0
      @needs_early_sort = false
      @block = block
      @reactor_size = 0
      @reactor_max = 0
    end

    # Run the internal select loop, using a background thread by default.
    def run(background=true)
      if background
        @thread = Thread.new do
          Puma.set_thread_name "reactor"
          select_loop
        end
      else
        select_loop
      end
    end

    # Add a new client to monitor.
    # The object must respond to #timeout and #timeout_at.
    # Returns false if the reactor is already shut down.
    def add(client)
      @input << client
      @selector.wakeup
      true
    rescue ClosedQueueError, IOError # Ignore if selector is already closed
      false
    end

    # Shutdown the reactor, blocking until the background thread is finished.
    def shutdown
      @input.close
      begin
        @selector.wakeup
      rescue IOError # Ignore if selector is already closed
      end
      @thread&.join
    end

    private

    def select_loop
      begin
        until @input.closed? && @input.empty?
          # Wakeup any registered object that receives incoming data.
          # Block until the earliest timeout or Selector#wakeup is called.
          timeout = next_timeout
          @selector.select(timeout) do |monitor|
            wakeup!(monitor.value)
          end

          # Wakeup all objects that timed out.
          @early_earliest ||= @early_timeouts.each_key { |k| break k } unless @early_timeouts.empty?
          expire_timeouts(@early_timeouts) if @early_earliest && @early_earliest.timeout == 0
          @earliest ||= @timeouts.each_key { |k| break k } unless @timeouts.empty?
          expire_timeouts(@timeouts) if @earliest && @earliest.timeout == 0

          unless @input.empty?
            until @input.empty?
              client = @input.pop
              register(client) if client.io_ok?
            end
            if @needs_early_sort
              sorted = @early_timeouts.keys.sort_by!(&:timeout_at)
              @early_timeouts.clear
              sorted.each { |c| @early_timeouts[c] = true }
              @early_earliest = sorted.first
              @early_last_timeout_at = sorted.last&.timeout_at || 0.0
              @needs_early_sort = false
            end
          end
        end
      rescue StandardError => e
        STDERR.puts "Error in reactor loop escaped: #{e.message} (#{e.class})"
        STDERR.puts e.backtrace

        retry
      end

      # Wakeup all remaining objects on shutdown.
      @early_timeouts.each_key(&@block)
      @timeouts.each_key(&@block)
      @selector.close
    end

    def next_timeout
      @earliest ||= @timeouts.each_key { |k| break k } unless @timeouts.empty?
      @early_earliest ||= @early_timeouts.each_key { |k| break k } unless @early_timeouts.empty?
      t1 = @earliest&.timeout
      t2 = @early_earliest&.timeout
      if t1 && t2
        t1 < t2 ? t1 : t2
      else
        t1 || t2
      end
    end

    def expire_timeouts(map)
      timed_out = []
      map.each_key do |client|
        break unless client.timeout == 0
        timed_out << client
      end
      timed_out.each { |client| wakeup!(client) }
      @earliest = (@timeouts.each_key { |k| break k } unless @timeouts.empty?)
      @early_earliest = (@early_timeouts.each_key { |k| break k } unless @early_timeouts.empty?)
    end

    # Start monitoring the object.
    def register(client)
      @selector.register(client.to_io, :r).value = client
      @reactor_size += 1
      @reactor_max = @reactor_size if @reactor_max < @reactor_size
      t_at = client.timeout_at
      if @timeouts.empty? || t_at >= @last_timeout_at
        @earliest = client if @timeouts.empty?
        @last_timeout_at = t_at
        @timeouts[client] = true
      else
        if @early_timeouts.empty?
          @early_earliest = client
          @early_last_timeout_at = t_at
        elsif t_at < @early_last_timeout_at
          @needs_early_sort = true
        else
          @early_last_timeout_at = t_at
        end
        @early_timeouts[client] = true
      end
    rescue ArgumentError
      # unreadable clients raise error when processed by NIO
    end

    # 'Wake up' a monitored object by calling the provided block.
    # Stop monitoring the object if the block returns `true`.
    def wakeup!(client)
      if @block.call client
        @selector.deregister client.to_io
        @reactor_size -= 1
        if @timeouts.delete client
          @earliest = nil if @earliest.equal?(client)
        elsif @early_timeouts.delete client
          @early_earliest = nil if @early_earliest.equal?(client)
        end
      end
    end
  end
end
