require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'
require 'puma/configuration'
require 'puma/binder'
require 'puma/detect'
require 'puma/daemon_ext'
require 'puma/util'
require 'puma/single'
require 'puma/cluster'

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
      @debug = false
      @argv = argv
      @stdout = stdout
      @stderr = stderr

      @events = Events.new @stdout, @stderr

      @status = nil
      @runner = nil

      @config = nil

      ENV['NEWRELIC_DISPATCHER'] ||= "puma"

      setup_options
      generate_restart_data

      @binder = Binder.new(@events)
      @binder.import_from_env
    end

    # The Binder object containing the sockets bound to.
    attr_reader :binder

    # The Configuration object used.
    attr_reader :config

    # The Hash of options used to configure puma.
    attr_reader :options

    # The Events object used to output information.
    attr_reader :events

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

    def debug(str)
      if @options[:debug]
        @events.log "- #{str}"
      end
    end

    def jruby?
      IS_JRUBY
    end

    def windows?
      RUBY_PLATFORM =~ /mswin32|ming32/
    end

    def unsupported(str, cond=true)
      return unless cond
      @events.error str
      raise UnsupportedOption
    end

    # Build the OptionParser object to handle the available options.
    #
    def setup_options
      @options = {
        :min_threads => 0,
        :max_threads => 16,
        :quiet => false,
        :debug => false,
        :binds => [],
        :workers => 0,
        :daemon => false,
        :worker_boot => []
      }

      @parser = OptionParser.new do |o|
        o.on "-b", "--bind URI", "URI to bind to (tcp://, unix://, ssl://)" do |arg|
          @options[:binds] << arg
        end

        o.on "-C", "--config PATH", "Load PATH as a config file" do |arg|
          @options[:config_file] = arg
        end

        o.on "--control URL", "The bind url to use for the control server",
                              "Use 'auto' to use temp unix server" do |arg|
          if arg
            @options[:control_url] = arg
          elsif jruby?
            unsupported "No default url available on JRuby"
          end
        end

        o.on "--control-token TOKEN",
             "The token to use as authentication for the control server" do |arg|
          @options[:control_auth_token] = arg
        end

        o.on "-d", "--daemon", "Daemonize the server into the background" do
          @options[:daemon] = true
          @options[:quiet] = true
        end

        o.on "--debug", "Log lowlevel debugging information" do
          @options[:debug] = true
        end

        o.on "--dir DIR", "Change to DIR before starting" do |d|
          @options[:directory] = d.to_s
          @options[:worker_directory] = d.to_s
        end

        o.on "-e", "--environment ENVIRONMENT",
             "The environment to run the Rack app on (default development)" do |arg|
          @options[:environment] = arg
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

        o.on "--preload", "Preload the app. Cluster mode only" do
          @options[:preload_app] = true
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          @options[:quiet] = true
        end

        o.on "-R", "--restart-cmd CMD",
             "The puma command to run during a hot restart",
             "Default: inferred" do |cmd|
          @options[:restart_cmd] = cmd
        end

        o.on "-S", "--state PATH", "Where to store the state details" do |arg|
          @options[:state] = arg
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

        o.on "-V", "--version", "Print the version information" do
          puts "puma version #{Puma::Const::VERSION}"
          exit 1
        end

        o.on "-w", "--workers COUNT",
                   "Activate cluster mode: How many worker processes to create" do |arg|
          @options[:workers] = arg.to_i
        end

      end

      @parser.banner = "puma <options> <rackup file>"

      @parser.on_tail "-h", "--help", "Show help" do
        log @parser
        exit 1
      end
    end

    def write_state
      write_pid

      require 'yaml'

      if path = @options[:state]
        state = { "pid" => Process.pid }

        cfg = @config.dup

        [ :logger, :worker_boot, :on_restart ].each { |o| cfg.options.delete o }

        state["config"] = cfg

        File.open(path, "w") do |f|
          f.write state.to_yaml
        end
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

        at_exit { delete_pidfile }
      end
    end

    def set_rack_environment
      # Try the user option first, then the environment variable,
      # finally default to development

      env = @options[:environment] ||
                   ENV['RACK_ENV'] ||
                     'development'

      @options[:environment] = env
      ENV['RACK_ENV'] = env
    end

    def delete_pidfile
      if path = @options[:pidfile]
        File.unlink path if File.exists? path
      end
    end

    # :nodoc:
    def parse_options
      @parser.parse! @argv

      if @argv.last
        @options[:rackup] = @argv.shift
      end

      @config = Puma::Configuration.new @options

      # Advertise the Configuration
      Puma.cli_config = @config

      @config.load

      if @options[:workers] > 0
        unsupported "worker mode not supported on JRuby and Windows",
                    jruby? || windows?
      end
    end

    def graceful_stop
      @control.stop(true) if @control
      @runner.stop_blocked
      log "- Goodbye!"
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
          @options[:worker_directory] = dir
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

        # Detect and reinject -Ilib from the command line
        lib = File.expand_path "lib"
        arg0[1,0] = ["-I", lib] if $:[0] == lib

        @restart_argv = arg0 + ARGV
      end
    end

    def restart_args
      if cmd = @options[:restart_cmd]
        cmd.split(' ') + @original_argv
      else
        @restart_argv
      end
    end

    def restart!
      @options[:on_restart].each do |block|
        block.call self
      end

      if jruby?
        @binder.listeners.each_with_index do |(str,io),i|
          io.close

          # We have to unlink a unix socket path that's not being used
          uri = URI.parse str
          if uri.scheme == "unix"
            path = "#{uri.host}#{uri.path}"
            File.unlink path
          end
        end

        require 'puma/jruby_restart'
        JRubyRestart.chdir_exec(@restart_dir, restart_args)
      else
        redirects = {:close_others => true}
        @binder.listeners.each_with_index do |(l,io),i|
          ENV["PUMA_INHERIT_#{i}"] = "#{io.to_i}:#{l}"
          redirects[io.to_i] = io.to_i
        end

        argv = restart_args

        Dir.chdir @restart_dir

        argv += [redirects] unless RUBY_VERSION < '1.9'
        Kernel.exec(*argv)
      end
    end
    # Parse the options, load the rackup, start the server and wait
    # for it to finish.
    #
    def run
      begin
        parse_options
      rescue UnsupportedOption
        exit 1
      end

      if dir = @options[:directory]
        Dir.chdir dir
      end

      clustered = @options[:workers] > 0

      if clustered
        @events = PidEvents.new STDOUT, STDERR
        @options[:logger] = @events
      end

      set_rack_environment

      if clustered
        @runner = Cluster.new(self)
      else
        @runner = Single.new(self)
      end

      setup_signals

      if cont = @options[:control_url]
        start_control cont
      end

      @status = :run

      @runner.run

      case @status
      when :halt
        log "* Stopping immediately!"
      when :run, :stop
        graceful_stop
      when :restart
        log "* Restarting..."
        @control.stop true if @control
        restart!
      end
    end

    def setup_signals
      begin
        Signal.trap "SIGUSR2" do
          restart
        end
      rescue Exception
        log "*** SIGUSR2 not implemented, signal based restart unavailable!"
      end

      begin
        Signal.trap "SIGTERM" do
          log " - Gracefully stopping, waiting for requests to finish"
          @runner.stop
        end
      rescue Exception
        log "*** SIGTERM not implemented, signal based gracefully stopping unavailable!"
      end

      if jruby?
        Signal.trap("INT") do
          graceful_stop
          exit
        end
      end
    end

    def start_control(str)
      require 'puma/app/status'

      uri = URI.parse str

      app = Puma::App::Status.new self

      if token = @options[:control_auth_token]
        app.auth_token = token unless token.empty? or token == :none
      end

      control = Puma::Server.new app, @events
      control.min_threads = 0
      control.max_threads = 1

      case uri.scheme
      when "tcp"
        log "* Starting control server on #{str}"
        control.add_tcp_listener uri.host, uri.port
      when "unix"
        log "* Starting control server on #{str}"
        path = "#{uri.host}#{uri.path}"

        control.add_unix_listener path
      else
        error "Invalid control URI: #{str}"
      end

      control.run
      @control = control
    end

    def stop
      @status = :stop
      @runner.stop
    end

    def restart
      @status = :restart
      @runner.restart
    end

    def phased_restart
      return false unless @runner.respond_to? :phased_restart
      @runner.phased_restart
    end

    def stats
      @runner.stats
    end

    def halt
      @status = :halt
      @runner.halt
    end
  end
end
