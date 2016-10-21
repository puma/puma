require 'puma/rack/builder'
require 'puma/plugin'

module Puma

  module ConfigDefault
    DefaultRackup = "config.ru"

    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292
    DefaultWorkerTimeout = 60
    DefaultWorkerShutdownTimeout = 30
  end

  class LeveledOptions
    def initialize(default_options, user_options)
      @cur = user_options
      @set = [@cur]
      @defaults = default_options.dup
    end

    def initialize_copy(other)
      @set = @set.map { |o| o.dup }
      @cur = @set.last
    end

    def shift
      @cur = {}
      @set << @cur
    end

    def [](key)
      @set.reverse_each do |o|
        if o.key? key
          return o[key]
        end
      end

      v = @defaults[key]
      if v.respond_to? :call
        v.call
      else
        v
      end
    end

    def fetch(key, default=nil)
      val = self[key]
      return val if val
      default
    end

    attr_reader :cur

    def all_of(key)
      all = []

      @set.each do |o|
        if v = o[key]
          if v.kind_of? Array
            all += v
          else
            all << v
          end
        end
      end

      all
    end

    def []=(key, val)
      @cur[key] = val
    end

    def key?(key)
      @set.each do |o|
        if o.key? key
          return true
        end
      end

      @default.key? key
    end

    def merge!(o)
      o.each do |k,v|
        @cur[k]= v
      end
    end

    def flatten
      options = {}

      @set.each do |o|
        o.each do |k,v|
          options[k] ||= v
        end
      end

      options
    end

    def explain
      indent = ""

      @set.each do |o|
        o.keys.sort.each do |k|
          puts "#{indent}#{k}: #{o[k].inspect}"
        end

        indent = "  #{indent}"
      end
    end

    def force_defaults
      @defaults.each do |k,v|
        if v.respond_to? :call
          @defaults[k] = v.call
        end
      end
    end
  end

  class Configuration
    include ConfigDefault

    def self.from_file(path)
      cfg = new

      DSL.new(cfg.options, cfg)._load_from path

      return cfg
    end

    def initialize(options={}, &blk)
      @options = LeveledOptions.new(default_options, options)

      @plugins = PluginLoader.new

      if blk
        configure(&blk)
      end
    end

    attr_reader :options, :plugins

    def configure(&blk)
      @options.shift
      DSL.new(@options, self)._run(&blk)
    end

    def initialize_copy(other)
      @conf = nil
      @cli_options = nil
      @options = @options.dup
    end

    def flatten
      dup.flatten!
    end

    def flatten!
      @options = @options.flatten
      self
    end

    def default_options
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
        :environment => lambda { ENV['RACK_ENV'] || "development" },
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
        @options.shift

        DSL.load @options, self, f
      end
    end

    # Call once all configuration (included from rackup files)
    # is loaded to flesh out any defaults
    def clamp
      @options.shift
      @options.force_defaults
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

      @options.shift

      rack_app, rack_options = rack_builder.parse_file(rackup)
      @options.merge!(rack_options)

      config_ru_binds = []
      rack_options.each do |k, v|
        config_ru_binds << v if k.to_s.start_with?("bind")
      end

      @options[:binds] = config_ru_binds unless config_ru_binds.empty?

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
