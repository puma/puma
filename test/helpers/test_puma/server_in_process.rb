# frozen_string_literal: true

require_relative "server_base"

require "puma/minissl" if ::Puma::HAS_SSL
require "puma/events"

module TestPuma

  # Creates in-process `Puma::Server`'s.  These can be created either by using
  # `#cli_run` (using `Puma::CLI.new.run`)  or `#server_run` (using `Puma::Server.new.run`).
  #
  class ServerInProcess < ServerBase
    include TestPuma
    include TestPuma::PumaSocket

    APP_URL_SCHEME = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    # Don't set anything if already set cia ctx proc
    DFLT_SSL_CTX = begin
      if ::Puma::HAS_SSL
        -> (ctx) {
          cert_path = File.expand_path "../../../examples/puma", __dir__
          if Puma::IS_JRUBY
            ctx.keystore      ||= "#{cert_path}/keystore.jks"
            ctx.keystore_pass ||= 'jruby_puma'
          elsif !(ctx.cert || ctx.cert_pem || ctx.key || ctx.key_pem)
            ctx.key  = "#{cert_path}/puma_keypair.pem"
            ctx.cert = "#{cert_path}/cert_puma.pem"
          end
          ctx.verify_mode ||= Puma::MiniSSL::VERIFY_NONE
        }
      else
        nil
      end
    end

    def before_setup
      @cli           = nil
      @cli_thread    = nil
      @events        = nil
      @log_writer    = nil
      @ready         = nil
      @server_ctx    = nil
      @server_thread = nil
      @wait          = nil
      super
    end

    def after_teardown
      @server&.stop true
      Thread.kill(@server_thread) if @server_thread&.alive?
      @server_ctx    = nil
      @server_thread = nil

      if @cli && @cli_thread
        @cli.launcher&.stop
        @cli_thread.join 5
        retries = 0
        loop do
          log = @log_writer.stdout.string
          break if log.include? 'Goodbye!'
          sleep 0.01
          Thread.pass
          retries += 1
          break if retries > 10
        end
        Thread.kill(@cli_thread) if @cli_thread.alive?
        @cli_thread = nil
      end
      super
    end

    # Creates a `Puma::Server` instance, runs it, and returns the thread or server instance.
    def server_run(app: APP_URL_SCHEME, ctx: DFLT_SSL_CTX, background: true, **options)
      options ||= {}
      server_new(options, app: app, ctx: ctx)
      server_new_run background: background
    end

    # Creates a `Puma::Server` instance. See `#server_run`
    def server_new(options = {}, app: APP_URL_SCHEME, ctx: DFLT_SSL_CTX)
      @log_writer = options[:log_writer] ||= Puma::LogWriter.strings
      options[:min_threads] ||= 1
      @events ||= Puma::Events.new

      @server = Puma::Server.new app, @events, options

      case @bind_type
      when :ssl
        if ctx.is_a? Puma::MiniSSL::Context
          @server_ctx = ctx
        elsif ctx == false
          # used for LocalhostAuthority testing
          @server_ctx = nil
        else
          @server_ctx = Puma::MiniSSL::Context.new
          ctx&.call @server_ctx
          DFLT_SSL_CTX.call @server_ctx # set defaults
        end
        @server.add_ssl_listener bind_host, 0, @server_ctx
        @bind_port = @server.connected_ports[0]
      when :tcp
        @server.add_tcp_listener bind_host, 0
        @bind_port = @server.connected_ports[0]
      when :unix, :aunix
        @server.add_unix_listener bind_path
      end
      @server
    end

    # Starts an existing `Puma::Server` instance.  Only used if an existing server
    # has been created with `#server_new`.
    #
    def server_new_run(background: true)
      min_threads = @server.instance_variable_get :@min_threads
      if background
        @server_thread = @server.run
      else
        @server.run false
      end
      until @server.running >= min_threads
        Thread.pass
        sleep 0.005
      end
      @server_thread
    end

    # Creates a server and runs it via a `Puma::CLI` instance.
    def cli_run(opts = [])
      cli_new opts
      @cli_thread = Thread.new { @cli.run }

      begin
        @wait.sysread 1
      rescue Errno::EAGAIN
        sleep 0.001
        retry
      end
    end

    # Creates a server via a `Puma::CLI` instance.
    def cli_new(opts = [])
      @wait, @ready = IO.pipe
      options = ['-b', bind_uri_str]
      options += set_pumactl_args.split(' ') if @control_type
      options += opts

      @log_writer = Puma::LogWriter.strings

      @events ||= Puma::Events.new
      @events.on_booted { @ready << "!" }

      @cli = Puma::CLI.new options, @log_writer, @events
    end
  end
end
