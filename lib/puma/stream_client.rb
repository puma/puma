module Puma
  # This serves as a base class for any plugin that wants to take over the
  # socket and wait on IO.
  #
  # The subclasses are expected to implement these two methods: `#read_more` &
  # `#churn`.
  #
  # The underlying socket is available through `@io`.
  class StreamClient
    def initialize(io)
      @io = io
    end

    def to_io
      @io
    end

    def stream?
      true
    end

    def timeout_at
      false
    end

    def close
      @io.close
    end

    def closed?
      @io.closed?
    end

    # This method will be invoked when the IO descriptor has new data pending
    # to be read. You can read from `@io` at this time.
    #
    # You can return a truthy value to add this client to the thread pool.
    def read_more
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
