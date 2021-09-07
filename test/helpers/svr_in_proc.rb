# frozen_string_literal: true

require_relative 'tmp_path'
require_relative 'svr_base'
require_relative 'sockets'

require "puma/configuration"
require "puma/events"
# avoids circular require when running single tests
require 'nio'

module TestPuma
  class SvrInProc < SvrBase
    include TmpPath
    include TestPuma::Sockets

    # Stops server, closes all members of `@ios_to_close`, verifies that listeners'
    # ports and/or files are closed.
    def teardown
      return if skipped?
      if @server
        @server.stop true
        @server.binder.close_listeners
      end

      if @ios_to_close
        @ios_to_close.each do |io|
          io.close if io.is_a?(IO) && !io.closed?
          io = nil
        end
      end

      if defined?(@bind_port) && @bind_port
        begin
          TCPServer.new(HOST, @bind_port).close
        rescue SystemCallError => e
          flunk "Bind socket should be closed (#{e.class} #{@bind_port})"
        end
      end

      if defined?(@bind_path) && @bind_path
        refute File.exist?(@bind_path), 'Bind path should be removed'
        File.unlink(@bind_path) rescue nil
      end
    end

    # Configures the server.
    # @param [Symbol] The type the type of listener socket.  Allowable values are
    #   :ssl, :tcp, :aunix, and :unix.
    # @param [String] config: a configuration string that is evaluated
    # @param [String] config_file: path to a config file
    # @param [Hash] ssl_opts: path to a config file
    # @note `config:` and `config_path:` parameters are mutually exclusive
    #
    def setup_server(type = :tcp, config: nil, config_path: nil, ssl_opts: nil)
      if config && config_path
        raise ArgumentError, "config: and config_path: cannot both be used"
      end
      unless BIND_TYPES.include? type
        raise ArgumentError, "Invalid argument #{type.inspect}"
      end
      @bind_type ||= type
      @config = config
      @config = File.read(config_path) if config_path
      @ssl_opts = ssl_opts
    end

    # Starts an in-process server (`Server`).
    # @param [Hash] opts options to be used
    # @param [Proc] block app to be passed to server
    #
    def start_server(opts = nil, &block)
      setup_server unless @bind_type # defaults to tcp

      if opts.is_a? Proc
        block = opts
        options = {}
      else
        options = opts || {}
      end

      options[:binds] ||= []
      if (t = options.delete :threads) && t =~ /\A\d+:\d+\z/
        min, max = t.split(':').map(&:to_i)
        options[:min_threads] = min
        options[:max_threads] = max
      end

      case @bind_type
      when :ssl
        @bind_port = UniquePort.call
        @bind_ssl = Puma::DSL.ssl_bind_str HOST, @bind_port,
          ssl_default_opts.merge(@ssl_opts)
        options[:binds] << @bind_ssl
      when :tcp
        @bind_port = UniquePort.call
        options[:binds] << "tcp://#{HOST}:#{@bind_port}"
      when :aunix
        require 'securerandom'
        @bind_path = "@#{SecureRandom.uuid}"
        options[:binds] << "unix://#{@bind_path}"
      when :unix
        @bind_path = tmp_path '.bind'
        options[:binds] << "unix://#{@bind_path}"
      end

      @events = Puma::Events.strings

      @conf = if @config
        Puma::Configuration.new(options) { |user_dsl, file_dsl, default_dsl|
          file_dsl.send(:instance_eval, @config)
        }.tap(&:clamp)
      else
        Puma::Configuration.new(options).tap(&:clamp)
      end

      @server = Puma::Server.new (block || @app), @events, @conf.options
      @server.inherit_binder Puma::Binder.new(@events, @conf)
      @server.binder.parse @conf.options[:binds], @events
      @server.run
      sleep 0.01
    end
  end
end
