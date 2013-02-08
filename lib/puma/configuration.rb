module Puma

  # The CLI exports it's Configuration object here to allow
  # apps to pick it up. An app needs to use it conditionally though
  # since it is not set if the app is launched via another
  # mechanism than the CLI class.

  class << self
    attr_accessor :cli_config
  end

  class Configuration
    DefaultRackup = "config.ru"

    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292

    def initialize(options)
      @options = options
      @options[:binds] ||= []
      @options[:on_restart] ||= []
    end

    attr_reader :options

    def initialize_copy(other)
      @options = @options.dup
    end

    def load
      if path = @options[:config_file]
        DSL.new(@options)._load_from path
      end

      # Rakeup default option support
      if host = @options[:Host]
        port = @options[:Port] || DefaultTCPPort

        @options[:binds] << "tcp://#{host}:#{port}"
      end

      if @options[:binds].empty?
        @options[:binds] << "tcp://#{DefaultTCPHost}:#{DefaultTCPPort}"
      end

      if @options[:control_url] == "auto"
        path = Configuration.temp_path
        @options[:control_url] = "unix://#{path}"
        @options[:control_url_temp] = path
      end

      unless @options[:control_auth_token]
        setup_random_token
      end
    end

    # Injects the Configuration object into the env
    class ConfigMiddleware
      def initialize(config, app)
        @config = config
        @app = app
      end

      def call(env)
        env[Const::PUMA_CONFIG] = @config
        @app.call(env)
      end
    end

    # Load the specified rackup file, pull an options from
    # the rackup file, and set @app.
    #
    def app
      app = @options[:app]

      unless app
        path = @options[:rackup] || DefaultRackup

        unless File.exists?(path)
          raise "Missing rackup file '#{path}'"
        end

        app, options = Rack::Builder.parse_file path
        @options.merge! options

        options.each do |key,val|
          if key.to_s[0,4] == "bind"
            @options[:binds] << val
          end
        end
      end

      if !@options[:quiet] and @options[:environment] == "development"
        logger = @options[:logger] || STDOUT
        app = Rack::CommonLogger.new(app, logger)
      end

      return ConfigMiddleware.new(self, app)
    end

    def setup_random_token
      begin
        require 'openssl'
      rescue LoadError
      end

      count = 16

      bytes = nil

      if defined? OpenSSL::Random
        bytes = OpenSSL::Random.random_bytes(count)
      elsif File.exists?("/dev/urandom")
        File.open("/dev/urandom") do |f|
          bytes = f.read(count)
        end
      end

      if bytes
        token = ""
        bytes.each_byte { |b| token << b.to_s(16) }
      else
        token = (0..count).to_a.map { rand(255).to_s(16) }.join
      end

      @options[:control_auth_token] = token
    end

    def self.temp_path
      require 'tmpdir'

      t = (Time.now.to_f * 1000).to_i
      "#{Dir.tmpdir}/puma-status-#{t}-#{$$}"
    end

    # The methods that are available for use inside the config file.
    #
    class DSL
      def initialize(options)
        @options = options
      end

      def _load_from(path)
        instance_eval File.read(path), path, 1
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
          if tok = opts[:auth_token]
            @options[:control_auth_token] = tok
          end

          if opts[:no_token]
            @options[:control_auth_token] = :none
          end
        end
      end

      # Bind the server to +url+. tcp:// and unix:// are the only accepted
      # protocols.
      #
      def bind(url)
        @options[:binds] << url
      end

      # Daemonize the server into the background. Highly suggest that
      # this be combined with +pidfile+ and +stdout_redirect+.
      def daemonize(which=true)
        @options[:daemon] = which
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
      def on_restart(&blk)
        @options[:on_restart] << blk
      end

      # Command to use to restart puma. This should be just how to
      # load puma itself (ie. 'ruby -Ilib bin/puma'), not the arguments
      # to puma, as those are the same as the original process.
      #
      def restart_command(cmd)
        @options[:request_cmd] = cmd
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
        if min > max
          raise "The minimum number of threads must be less than the max"
        end

        @options[:min_threads] = min
        @options[:max_threads] = max
      end

      def ssl_bind(host, port, opts)
        o = [
          "cert=#{opts[:cert]}",
          "key=#{opts[:key]}"
        ]

        @options[:binds] << "ssl://#{host}:#{port}?#{o.join('&')}"
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

      # *Cluster mode only* Code to run when a worker boots to setup
      # the process before booting the app.
      #
      # This can be called multiple times to add hooks.
      #
      def on_worker_boot(&block)
        @options[:worker_boot] << block
      end

      # The directory to operate out of.
      def directory(dir)
        @options[:directory] = dir.to_s
        @options[:worker_directory] = dir.to_s
      end
    end
  end
end
