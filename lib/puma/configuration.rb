module Puma

  module ConfigDefault
    DefaultRackup = "config.ru"

    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292
    DefaultWorkerTimeout = 60
    DefaultWorkerShutdownTimeout = 30
  end

  class Configuration
    include ConfigDefault

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

      setup_binds
      setup_control
      @options[:tag] ||= infer_tag
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
      found = options[:app] || load_rackup

      if @options[:mode] == :tcp
        require 'puma/tcp_logger'

        logger = @options[:logger] || STDOUT
        return TCPLogger.new(logger, found, @options[:quiet])
      end

      if !@options[:quiet] and @options[:environment] == "development"
        logger = @options[:logger] || STDOUT
        found = Rack::CommonLogger.new(found, logger)
      end

      ConfigMiddleware.new(self, found)
    end

    def self.temp_path
      require 'tmpdir'

      t = (Time.now.to_f * 1000).to_i
      "#{Dir.tmpdir}/puma-status-#{t}-#{$$}"
    end

    private

    def infer_tag
      File.basename(Dir.getwd)
    end

    def load_rackup
      raise "Missing rackup file '#{rackup}'" unless File.exist?(rackup)

      rack_app, rack_options = Rack::Builder.parse_file(rackup)
      @options.merge!(rack_options)

      config_ru_binds = rack_options.each_with_object([]) do |(k, v), b|
        b << v if k.to_s[0,4] == "bind"
      end
      @options[:binds] = config_ru_binds unless config_ru_binds.empty?

      rack_app
    end

    def setup_binds
      # Rakeup default option support
      host = @options[:Host]
      if host
        port = @options[:Port] || DefaultTCPPort
        @options[:binds] << "tcp://#{host}:#{port}"
      end

      if @options[:binds].empty?
        @options[:binds] << "tcp://#{DefaultTCPHost}:#{DefaultTCPPort}"
      end

      @options[:binds].uniq!
    end

    def setup_control
      if @options[:control_url] == 'auto'
        path = Configuration.temp_path
        @options[:control_url] = "unix://#{path}"
        @options[:control_url_temp] = path
      end

      setup_random_token unless @options[:control_auth_token]
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
        File.open('/dev/urandom') { |f| bytes = f.read(count) }
      end

      if bytes
        token = ""
        bytes.each_byte { |b| token << b.to_s(16) }
      else
        token = (0..count).to_a.map { rand(255).to_s(16) }.join
      end

      @options[:control_auth_token] = token
    end
  end
end

require 'puma/dsl'
