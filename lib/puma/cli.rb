require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'
require 'puma/configuration'
require 'puma/detect'

require 'rack/commonlogger'
require 'rack/utils'

module Puma
  # Handles invoke a Puma::Server in a command line style.
  #
  class CLI
    # Create a new CLI object using +argv+ as the command line
    # arguments.
    #
    # +stdout+ and +stderr+ can be set to IO-like objects which
    # this object will report status on.
    #
    def initialize(argv, stdout=STDOUT, stderr=STDERR)
      @argv = argv
      @stdout = stdout
      @stderr = stderr

      @events = Events.new @stdout, @stderr

      @server = nil
      @status = nil

      @restart = false

      @listeners = []

      setup_options

      generate_restart_data

      @inherited_fds = {}
      remove = []

      ENV.each do |k,v|
        if k =~ /PUMA_INHERIT_\d+/
          fd, url = v.split(":", 2)
          @inherited_fds[url] = fd.to_i
          remove << k
        end
      end

      remove.each do |k|
        ENV.delete k
      end
    end

    def restart_on_stop!
      @restart = true
    end

    def generate_restart_data
      # Use the same trick as unicorn, namely favor PWD because
      # it will contain an unresolved symlink, useful for when
      # the pwd is /data/releases/current.
      if dir = ENV['PWD']
        s_env = File.stat(dir)
        s_pwd = File.stat(Dir.pwd)

        if s_env.ino == s_pwd.ino and s_env.dev == s_pwd.dev
          @restart_dir = dir
        end
      end

      @restart_dir ||= Dir.pwd

      @original_argv = ARGV.dup

      if defined? Rubinius::OS_ARGV
        @restart_argv = Rubinius::OS_ARGV
      else
        require 'rubygems'

        # if $0 is a file in the current directory, then restart
        # it the same, otherwise add -S on there because it was
        # picked up in PATH.
        #
        if File.exists?($0)
          arg0 = [Gem.ruby, $0]
        else
          arg0 = [Gem.ruby, "-S", $0]
        end

        @restart_argv = arg0 + ARGV
      end
    end

    def restart!
      @options[:on_restart].each do |blk|
        blk.call self
      end

      if IS_JRUBY
        @listeners.each_with_index do |(str,io),i|
          io.close

          # We have to unlink a unix socket path that's not being used
          uri = URI.parse str
          if uri.scheme == "unix"
            path = "#{uri.host}#{uri.path}"
            File.unlink path
          end
        end

        require 'puma/jruby_restart'
        JRubyRestart.chdir_exec(@restart_dir, Gem.ruby, *@restart_argv)
      else
        @listeners.each_with_index do |(l,io),i|
          ENV["PUMA_INHERIT_#{i}"] = "#{io.to_i}:#{l}"
        end

        if cmd = @options[:restart_cmd]
          argv = cmd.split(' ') + @original_argv
        else
          argv = @restart_argv
        end

        Dir.chdir @restart_dir
        Kernel.exec(*argv)
      end
    end

    # Delegate +log+ to +@events+
    #
    def log(str)
      @events.log str
    end

    # Delegate +error+ to +@events+
    #
    def error(str)
      @events.error str
    end

    # Build the OptionParser object to handle the available options.
    #
    def setup_options
      @options = {
        :min_threads => 0,
        :max_threads => 16,
        :quiet => false,
        :binds => []
      }

      @parser = OptionParser.new do |o|
        o.on "-b", "--bind URI", "URI to bind to (tcp:// and unix:// only)" do |arg|
          @options[:binds] << arg
        end

        o.on "-C", "--config PATH", "Load PATH as a config file" do |arg|
          @options[:config_file] = arg
        end

        o.on "-I", "--include PATH", "Specify $LOAD_PATH directories" do |arg|
          $LOAD_PATH.unshift(*arg.split(':'))
        end

        o.on "-p", "--port PORT", "Define what port TCP port to bind to",
                                  "Use -b for more advanced options" do |arg|
          @options[:binds] << "tcp://#{Configuration::DefaultTCPHost}:#{arg}"
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          @options[:pidfile] = arg
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          @options[:quiet] = true
        end

        o.on "-S", "--state PATH", "Where to store the state details" do |arg|
          @options[:state] = arg
        end

        o.on "--control URL", "The bind url to use for the control server",
                              "Use 'auto' to use temp unix server" do |arg|
          if arg
            @options[:control_url] = arg
          elsif IS_JRUBY
            raise NotImplementedError, "No default url available on JRuby"
          end
        end

        o.on "--control-token TOKEN",
             "The token to use as authentication for the control server" do |arg|
          @options[:control_auth_token] = arg
        end

        o.on '-t', '--threads INT', "min:max threads to use (default 0:16)" do |arg|
          min, max = arg.split(":")
          if max
            @options[:min_threads] = min.to_i
            @options[:max_threads] = max.to_i
          else
            @options[:min_threads] = 0
            @options[:max_threads] = arg.to_i
          end
        end

        o.on "--restart-cmd CMD",
             "The puma command to run during a hot restart",
             "Default: inferred" do |cmd|
          @options[:restart_cmd] = cmd
        end

        o.on "-e", "--environment ENVIRONMENT",
             "The environment to run the Rack app on (default development)" do |arg|
          @options[:environment] = arg
        end
      end

      @parser.banner = "puma <options> <rackup file>"

      @parser.on_tail "-h", "--help", "Show help" do
        log @parser
        exit 1
      end
    end

    # If configured, write the pid of the current process out
    # to a file.
    #
    def write_pid
      if path = @options[:pidfile]
        File.open(path, "w") do |f|
          f.puts Process.pid
        end
      end
    end

    def set_rack_environment 
      # Try the user option first, then the environment variable,
      # finally default to development

      ENV['RACK_ENV'] = @options[:environment] ||
                        ENV['RACK_ENV'] ||
                        'development'
    end

    def delete_pidfile
      if path = @options[:pidfile]
        File.unlink path
      end
    end

    def write_state
      require 'yaml'

      if path = @options[:state]
        state = { "pid" => Process.pid }

        cfg = @config.dup
        cfg.options.delete :on_restart

        state["config"] = cfg

        File.open(path, "w") do |f|
          f.write state.to_yaml
        end
      end
    end

    # :nodoc:
    def parse_options
      @parser.parse! @argv

      if @argv.last
        @options[:rackup] = @argv.shift
      end

      @config = Puma::Configuration.new @options
      @config.load
    end

    def graceful_stop(server)
      log " - Gracefully stopping, waiting for requests to finish"
      server.stop(true)
      delete_pidfile
      log " - Goodbye!"
    end

    # Parse the options, load the rackup, start the server and wait
    # for it to finish.
    #
    def run
      parse_options

      set_rack_environment

      app = @config.app

      write_pid
      write_state

      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      server = Puma::Server.new app, @events
      server.min_threads = min_t
      server.max_threads = max_t

      log "Puma #{Puma::Const::PUMA_VERSION} starting..."
      log "* Min threads: #{min_t}, max threads: #{max_t}"
      log "* Environment: #{ENV['RACK_ENV']}"

      @options[:binds].each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          if fd = @inherited_fds.delete(str)
            log "* Inherited #{str}"
            io = server.inherit_tcp_listener uri.host, uri.port, fd
          else
            log "* Listening on #{str}"
            io = server.add_tcp_listener uri.host, uri.port
          end

          @listeners << [str, io]
        when "unix"
          path = "#{uri.host}#{uri.path}"

          if fd = @inherited_fds.delete(str)
            log "* Inherited #{str}"
            io = server.inherit_unix_listener path, fd
          else
            log "* Listening on #{str}"

            umask = nil

            if uri.query
              params = Rack::Utils.parse_query uri.query
              if u = params['umask']
                # Use Integer() to respect the 0 prefix as octal
                umask = Integer(u)
              end
            end

            io = server.add_unix_listener path, umask
          end

          @listeners << [str, io]
        when "ssl"
          params = Rack::Utils.parse_query uri.query
          require 'openssl'

          ctx = OpenSSL::SSL::SSLContext.new
          unless params['key']
            error "Please specify the SSL key via 'key='"
          end

          ctx.key = OpenSSL::PKey::RSA.new File.read(params['key'])

          unless params['cert']
            error "Please specify the SSL cert via 'cert='"
          end

          ctx.cert = OpenSSL::X509::Certificate.new File.read(params['cert'])

          ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE

          if fd = @inherited_fds.delete(str)
            log "* Inherited #{str}"
            io = server.inherited_ssl_listener fd, ctx
          else
            log "* Listening on #{str}"
            io = server.add_ssl_listener uri.host, uri.port, ctx
          end

          @listeners << [str, io]
        else
          error "Invalid URI: #{str}"
        end
      end

      # If we inherited fds but didn't use them (because of a
      # configuration change), then be sure to close them.
      @inherited_fds.each do |str, fd|
        log "* Closing unused inherited connection: #{str}"

        begin
          IO.for_fd(fd).close
        rescue SystemCallError
        end

        # We have to unlink a unix socket path that's not being used
        uri = URI.parse str
        if uri.scheme == "unix"
          path = "#{uri.host}#{uri.path}"
          File.unlink path
        end
      end

      @server = server

      if str = @options[:control_url]
        require 'puma/app/status'

        uri = URI.parse str

        app = Puma::App::Status.new server, self

        if token = @options[:control_auth_token]
          app.auth_token = token unless token.empty? or token == :none
        end

        status = Puma::Server.new app, @events
        status.min_threads = 0
        status.max_threads = 1

        case uri.scheme
        when "tcp"
          log "* Starting status server on #{str}"
          status.add_tcp_listener uri.host, uri.port
        when "unix"
          log "* Starting status server on #{str}"
          path = "#{uri.host}#{uri.path}"

          status.add_unix_listener path
        else
          error "Invalid status URI: #{str}"
        end

        status.run
        @status = status
      end

      begin
        Signal.trap "SIGUSR2" do
          @restart = true
          server.begin_restart
        end
      rescue Exception
        log "*** Sorry signal SIGUSR2 not implemented, restart feature disabled!"
      end

      begin
        Signal.trap "SIGTERM" do
          log " - Gracefully stopping, waiting for requests to finish"
          server.stop false
        end
      rescue Exception
        log "*** Sorry signal SIGTERM not implemented, gracefully stopping feature disabled!"
      end

      log "Use Ctrl-C to stop"

      begin
        server.run.join
      rescue Interrupt
        graceful_stop server
      end

      if @restart
        log "* Restarting..."
        @status.stop true if @status
        restart!
      end
    end

    def stop
      @server.stop(true) if @server
      delete_pidfile
    end
  end
end
