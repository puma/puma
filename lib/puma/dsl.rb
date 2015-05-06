module Puma
  # The methods that are available for use inside the config file.
  #
  class DSL
    include ConfigDefault

    def self.load(options, path)
      new(options).tap do |obj|
        obj._load_from(path)
      end

      options
    end

    def initialize(options)
      @options = options
    end

    def _load_from(path)
      instance_eval(File.read(path), path, 1) if path
    end

    # Use +obj+ or +block+ as the Rack app. This allows a config file to
    # be the app itself.
    #
    def app(obj=nil, &block)
      obj ||= block

      raise "Provide either a #call'able or a block" unless obj

      @options[:app] = obj
    end

    # Start the Puma control rack app on +url+. This app can be communicated
    # with to control the main server.
    #
    def activate_control_app(url="auto", opts=nil)
      @options[:control_url] = url

      if opts
        auth_token = opts[:auth_token]
        @options[:control_auth_token] = auth_token if auth_token

        @options[:control_auth_token] = :none if opts[:no_token]
      end
    end

    # Bind the server to +url+. tcp:// and unix:// are the only accepted
    # protocols.
    #
    def bind(url)
      @options[:binds] << url
    end

    # Define the TCP port to bind to. Use +bind+ for more advanced options.
    #
    def port(port)
      @options[:binds] << "tcp://#{Configuration::DefaultTCPHost}:#{port}"
    end

    # Work around leaky apps that leave garbage in Thread locals
    # across requests
    #
    def clean_thread_locals(which=true)
      @options[:clean_thread_locals] = which
    end

    # Daemonize the server into the background. Highly suggest that
    # this be combined with +pidfile+ and +stdout_redirect+.
    def daemonize(which=true)
      @options[:daemon] = which
    end

    # When shutting down, drain the accept socket of pending
    # connections and proces them. This loops over the accept
    # socket until there are no more read events and then stops
    # looking and waits for the requests to finish.
    def drain_on_shutdown(which=true)
      @options[:drain_on_shutdown] = which
    end

    # Set the environment in which the Rack's app will run.
    def environment(environment)
      @options[:environment] = environment
    end

    # Code to run before doing a restart. This code should
    # close logfiles, database connections, etc.
    #
    # This can be called multiple times to add code each time.
    #
    def on_restart(&block)
      @options[:on_restart] << block
    end

    # Command to use to restart puma. This should be just how to
    # load puma itself (ie. 'ruby -Ilib bin/puma'), not the arguments
    # to puma, as those are the same as the original process.
    #
    def restart_command(cmd)
      @options[:restart_cmd] = cmd
    end

    # Store the pid of the server in the file at +path+.
    def pidfile(path)
      @options[:pidfile] = path
    end

    # Disable request logging.
    #
    def quiet
      @options[:quiet] = true
    end

    # Load +path+ as a rackup file.
    #
    def rackup(path)
      @options[:rackup] = path.to_s
    end

    # Redirect STDOUT and STDERR to files specified.
    def stdout_redirect(stdout=nil, stderr=nil, append=false)
      @options[:redirect_stdout] = stdout
      @options[:redirect_stderr] = stderr
      @options[:redirect_append] = append
    end

    # Configure +min+ to be the minimum number of threads to use to answer
    # requests and +max+ the maximum.
    #
    def threads(min, max)
      min = Integer(min)
      max = Integer(max)
      if min > max
        raise "The minimum (#{min}) number of threads must be less than the max (#{max})"
      end

      @options[:min_threads] = min
      @options[:max_threads] = max
    end

    def ssl_bind(host, port, opts)
      @options[:binds] << "ssl://#{host}:#{port}?cert=#{opts[:cert]}&key=#{opts[:key]}"
    end

    # Use +path+ as the file to store the server info state. This is
    # used by pumactl to query and control the server.
    #
    def state_path(path)
      @options[:state] = path.to_s
    end

    # *Cluster mode only* How many worker processes to run.
    #
    def workers(count)
      @options[:workers] = count.to_i
    end

    # *Cluster mode only* How many worker processes to restart at a time,
    # when doing a phased restart.
    #
    def phased_restart_batch_count(count)
      @options[:phased_restart_batch_count] = count.to_i
    end

    # *Cluster mode only* Code to run immediately before a worker shuts
    # down (after it has finished processing HTTP requests). These hooks
    # can block if necessary to wait for background operations unknown
    # to puma to finish before the process terminates.
    #
    # This can be called multiple times to add hooks.
    #
    def on_worker_shutdown(&block)
      @options[:before_worker_shutdown] << block
    end

    # *Cluster mode only* Code to run when a worker boots to setup
    # the process before booting the app.
    #
    # This can be called multiple times to add hooks.
    #
    def on_worker_boot(&block)
      @options[:before_worker_boot] << block
    end

    # *Cluster mode only* Code to run when a master process is
    # about to create the worker by forking itself.
    #
    # This can be called multiple times to add hooks.
    #
    def on_worker_fork(&block)
      @options[:before_worker_fork] << block
    end

    # *Cluster mode only* Code to run when a worker boots to setup
    # the process after booting the app.
    #
    # This can be called multiple times to add hooks.
    #
    def after_worker_boot(&block)
      @options[:after_worker_boot] << block
    end

    # The directory to operate out of.
    def directory(dir)
      @options[:directory] = dir.to_s
      @options[:worker_directory] = dir.to_s
    end

    # Run the app as a raw TCP app instead of an HTTP rack app
    def tcp_mode
      @options[:mode] = :tcp
    end

    # *Cluster mode only* Preload the application before starting
    # the workers and setting up the listen ports. This conflicts
    # with using the phased restart feature, you can't use both.
    #
    def preload_app!(answer=true)
      @options[:preload_app] = answer
    end

    # Use +obj+ or +block+ as the low level error handler. This allows a config file to
    # change the default error on the server.
    #
    def lowlevel_error_handler(obj=nil, &block)
      obj ||= block
      raise "Provide either a #call'able or a block" unless obj
      @options[:lowlevel_error_handler] = obj
    end

    # This option is used to allow your app and its gems to be
    # properly reloaded when not using preload.
    #
    # When set, if puma detects that it's been invoked in the
    # context of Bundler, it will cleanup the environment and
    # re-run itself outside the Bundler environment, but directly
    # using the files that Bundler has setup.
    #
    # This means that puma is now decoupled from your Bundler
    # context and when each worker loads, it will be loading a
    # new Bundler context and thus can float around as the release
    # dictates.
    def prune_bundler(answer=true)
      @options[:prune_bundler] = answer
    end

    # Additional text to display in process listing
    def tag(string)
      @options[:tag] = string
    end

    # *Cluster mode only* Set the timeout for workers
    def worker_timeout(timeout)
      @options[:worker_timeout] = timeout
    end

    # *Cluster mode only* Set the timeout for worker shutdown
    def worker_shutdown_timeout(timeout)
      @options[:worker_shutdown_timeout] = timeout
    end

    # When set to true (the default), workers accept all requests
    # and queue them before passing them to the handlers.
    # When set to false, each worker process accepts exactly as
    # many requests as it is configured to simultaneously handle.
    #
    # Queueing requests generally improves performance. In some
    # cases, such as a single threaded application, it may be
    # better to ensure requests get balanced across workers.
    #
    # Note that setting this to false disables HTTP keepalive and
    # slow clients will occupy a handler thread while the request
    # is being sent. A reverse proxy, such as nginx, can handle
    # slow clients and queue requests before they reach puma.
    def queue_requests(answer=true)
      @options[:queue_requests] = answer
    end

    # When a shutdown is requested, the backtraces of all the
    # threads will be written to $stdout. This can help figure
    # out why shutdown is hanging.
    def shutdown_debug(val=true)
      @options[:shutdown_debug] = val
    end
  end
end
