require 'puma/dsl'

module Puma
  class Configuration
    DefaultRackup = "config.ru"

    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292
    DefaultWorkerTimeout = 60
    DefaultWorkerShutdownTimeout = 30

    def initialize(options)
      @options = options
      @options[:mode] ||= :http
      @options[:binds] ||= []
      @options[:on_restart] ||= []
      @options[:before_worker_shutdown] ||= []
      @options[:before_worker_boot] ||= []
      @options[:before_worker_fork] ||= []
      @options[:after_worker_boot] ||= []
      @options[:worker_timeout] ||= DefaultWorkerTimeout
      @options[:worker_shutdown_timeout] ||= DefaultWorkerShutdownTimeout
    end

    attr_reader :options

    def initialize_copy(other)
      @options = @options.dup
    end

    def load
      DSL.load(@options, @options[:config_file])

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

      unless @options[:tag]
        @options[:tag] = infer_tag
      end

      @options[:binds].uniq!
    end

    def infer_tag
      File.basename Dir.getwd
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

    # Indicate if there is a properly configured app
    #
    def app_configured?
      @options[:app] || File.exist?(rackup)
    end

    def rackup
      @options[:rackup] || DefaultRackup
    end

    # Load the specified rackup file, pull options from
    # the rackup file, and set @app.
    #
    def app
      app = @options[:app]

      unless app
        unless File.exist?(rackup)
          raise "Missing rackup file '#{rackup}'"
        end

        app, options = Rack::Builder.parse_file rackup
        @options.merge! options

        config_ru_binds = []

        options.each do |key,val|
          if key.to_s[0,4] == "bind"
            config_ru_binds << val
          end
        end

        @options[:binds] = config_ru_binds unless config_ru_binds.empty?
      end

      if @options[:mode] == :tcp
        require 'puma/tcp_logger'

        logger = @options[:logger] || STDOUT
        return TCPLogger.new(logger, app, @options[:quiet])
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
      elsif File.exist?("/dev/urandom")
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

  end
end
