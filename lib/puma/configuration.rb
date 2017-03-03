require 'puma/rack/builder'
require 'puma/plugin'
require 'puma/const'

module Puma

  module ConfigDefault
    DefaultRackup = "config.ru"

    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292
    DefaultWorkerTimeout = 60
    DefaultWorkerShutdownTimeout = 30
  end

  # A class used for storing configuration options
  # Options can be provided directly via the cli i.e. `puma -p 3001`
  # or via a config file or multiple config files, or set as a default value
  #
  class UserFileDefaultOptions
    def initialize(user_options, default_options)
      @user_options    = user_options
      @file_options    = {}
      @default_options = default_options
    end

    attr_reader :user_options, :file_options, :default_options

    def [](key)
      return user_options[key]    if user_options.key?(key)
      return file_options[key]    if file_options.key?(key)
      return default_options[key] if default_options.key?(key)
    end

    def []=(key, value)
      user_options[key] = value
    end

    def fetch(key, default_value = nil)
      self[key] || default_value
    end

    def all_of(key)
      user    = user_options[key]
      file    = file_options[key]
      default = default_options[key]

      user    = [user]    unless user.is_a?(Array)
      file    = [file]    unless file.is_a?(Array)
      default = [default] unless default.is_a?(Array)

      user.compact!
      file.compact!
      default.compact!

      user + file + default
    end

    def finalize_values
      @default_options.each do |k,v|
        if v.respond_to? :call
          @default_options[k] = v.call
        end
      end
    end
  end


  class Configuration
    include ConfigDefault

    def self.from_file(path)
      cfg = new

      @file_dsl._load_from(path)

      return cfg
    end

    def initialize(options={}, default_options = {}, &blk)
      default_options = self.puma_default_options.merge(default_options)

      @options  = UserFileDefaultOptions.new(options, default_options)
      @plugins  = PluginLoader.new
      @user_dsl    = DSL.new(@options.user_options, self)
      @file_dsl    = DSL.new(@options.file_options, self)
      @default_dsl = DSL.new(@options.default_options, self)

      if blk
        configure(&blk)
      end
    end

    attr_reader :options, :plugins

    def configure(&blk)
      blk.call(@user_dsl, @file_dsl, @default_dsl)
    ensure
      @user_dsl._offer_plugins
      @file_dsl._offer_plugins
      @default_dsl._offer_plugins
    end

    def initialize_copy(other)
      @conf        = nil
      @cli_options = nil
      @options     = @options.dup
    end

    def flatten
      dup.flatten!
    end

    def flatten!
      @options = @options.flatten
      self
    end

    def puma_default_options
      {
        :min_threads => 0,
        :max_threads => 16,
        :log_requests => false,
        :debug => false,
        :binds => ["tcp://#{DefaultTCPHost}:#{DefaultTCPPort}"],
        :workers => 0,
        :daemon => false,
        :mode => :http,
        :worker_timeout => DefaultWorkerTimeout,
        :worker_boot_timeout => DefaultWorkerTimeout,
        :worker_shutdown_timeout => DefaultWorkerShutdownTimeout,
        :remote_address => :socket,
        :tag => method(:infer_tag),
        :environment => ->{ ENV['RACK_ENV'] || "development" },
        :rackup => DefaultRackup,
        :logger => STDOUT,
        :persistent_timeout => Const::PERSISTENT_TIMEOUT
      }
    end

    def load
      files = @options.all_of(:config_files)

      if files.empty?
        imp = %W(config/puma/#{@options[:environment]}.rb config/puma.rb).find { |f|
          File.exist?(f)
        }

        files << imp
      elsif files == ["-"]
        files = []
      end

      files.each do |f|
        @file_dsl.load(f)
      end
      @options
    end

    # Call once all configuration (included from rackup files)
    # is loaded to flesh out any defaults
    def clamp
      @options.finalize_values
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
      @options[:rackup]
    end

    # Load the specified rackup file, pull options from
    # the rackup file, and set @app.
    #
    def app
      found = options[:app] || load_rackup

      if @options[:mode] == :tcp
        require 'puma/tcp_logger'

        logger = @options[:logger]
        quiet = !@options[:log_requests]
        return TCPLogger.new(logger, found, quiet)
      end

      if @options[:log_requests]
        require 'puma/commonlogger'
        logger = @options[:logger]
        found = CommonLogger.new(found, logger)
      end

      ConfigMiddleware.new(self, found)
    end

    # Return which environment we're running in
    def environment
      @options[:environment]
    end

    def load_plugin(name)
      @plugins.create name
    end

    def run_hooks(key, arg)
      @options.all_of(key).each { |b| b.call arg }
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

    # Load and use the normal Rack builder if we can, otherwise
    # fallback to our minimal version.
    def rack_builder
      # Load bundler now if we can so that we can pickup rack from
      # a Gemfile
      if ENV.key? 'PUMA_BUNDLER_PRUNED'
        begin
          require 'bundler/setup'
        rescue LoadError
        end
      end

      begin
        require 'rack'
        require 'rack/builder'
      rescue LoadError
        # ok, use builtin version
        return Puma::Rack::Builder
      else
        return ::Rack::Builder
      end
    end

    def load_rackup
      raise "Missing rackup file '#{rackup}'" unless File.exist?(rackup)

      rack_app, rack_options = rack_builder.parse_file(rackup)
      @options.file_options.merge!(rack_options)

      config_ru_binds = []
      rack_options.each do |k, v|
        config_ru_binds << v if k.to_s.start_with?("bind")
      end

      @options.file_options[:binds] = config_ru_binds unless config_ru_binds.empty?

      rack_app
    end

    def self.random_token
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

      return token
    end
  end
end

require 'puma/dsl'
