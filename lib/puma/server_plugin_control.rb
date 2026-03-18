module Puma
  # ServerPluginControl provides a control interface for server plugins to
  # interact with and manage server settings dynamically.
  #
  # This class acts as a facade between plugins and the Puma server,
  # allowing plugins to safely modify server configuration and thread pool
  # settings without direct access to the server's internal state.
  #
  class ServerPluginControl
    def initialize(server)
      @server = server
    end

    # Returns the maximum number of threads in the thread pool.
    def max_threads
      @server.max_threads
    end

    # Returns the minimum number of threads in the thread pool.
    def min_threads
      @server.min_threads
    end

    # Updates the minimum and maximum number of threads in the thread pool.
    #
    # @see Puma::Server#update_thread_pool_min_max
    #
    def update_thread_pool_min_max(min: max_threads, max: min_threads)
      @server.update_thread_pool_min_max(min: min, max: max)
    end
  end
end
