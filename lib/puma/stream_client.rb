module Puma
  # This serves as a base class for any plugin that wants to take over the
  # socket and wait on IO.
  #
  # The subclasses are expected to implement:
  #
  #  1. Methods to respond to changes in the underlying socket. These are
  #     `#on_read_ready`, `#on_broken_pipe` & `#on_shutdown`.
  #  2. A `#churn` method that runs within the thread pool, this is what can
  #     be used to invoke app's logic.
  #
  # The underlying socket is available through `@io`.
  #
  # The other methods should never be overriden.
  class StreamClient
    def initialize(io)
      @io = io
    end

    def to_io
      @io
    end

    def timeout_at
      false
    end

    def closed?
      @io.closed?
    end

    def stream?
      true
    end

    # This method will be invoked when the IO descriptor has new data pending
    # to be read. You can read from `@io` at this time.
    #
    # You can return a truthy value to add this client to the thread pool.
    def on_read_ready
      raise NotImplementedError
    end

    # This method will be invoked when the underlying connection is broken
    # for whatever reason (client timeout, abrupt client disconnection, etc.).
    #
    # You can return a truthy value to add this client to the thread pool.
    def on_broken_pipe
      raise NotImplementedError
    end

    # This method will be invoked when the server is being stopped.
    #
    # It's not possible to run more work on the thread pool at this stage.
    def on_shutdown
      raise NotImplementedError
    end

    # This is the method that the thread pool will be consuming. A "churn" is
    # enqueued on the thread pool each time `#churn` or `#read_more` return a
    # truthy value.
    #
    # You can return a truthy value to add this client to the thread pool
    # again.
    def churn
      raise NotImplementedError
    end
  end
end
