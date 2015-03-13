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
    def initialize(argv, events=Events.stdio)
      @debug = false
      @argv = argv

      @events = events

      @status = nil
      @runner = nil

      @config = nil
      @options = default_options

      ENV['NEWRELIC_DISPATCHER'] ||= "Puma"

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

    def default_options
      {
        min_threads: 0,
        max_threads: 16,
        quiet: false,
        debug: false,
        binds: [],
        workers: 0,
        daemon: false,
        before_worker_shutdown: [],
        before_worker_boot: [],
        before_worker_fork: [],
        after_worker_boot: []
      }
    end

    def parse_argv(argv)
      parsed = { binds: [] }
      parser = OptionParser.new do |o|
        o.on "-b", "--bind URI", "URI to bind to (tcp://, unix://, ssl://)" do |arg|
          parsed[:binds] << arg
        end

        o.on "-C", "--config PATH", "Load PATH as a config file" do |arg|
          parsed[:config_file] = arg
        end

        o.on "--control URL", "The bind url to use for the control server",
                              "Use 'auto' to use temp unix server" do |arg|
          if arg
            parsed[:control_url] = arg
          elsif jruby?
            unsupported "No default url available on JRuby"
          end
        end

        o.on "--control-token TOKEN",
             "The token to use as authentication for the control server" do |arg|
          parsed[:control_auth_token] = arg
        end

        o.on "-d", "--daemon", "Daemonize the server into the background" do
          parsed[:daemon] = true
          parsed[:quiet] = true
        end

        o.on "--debug", "Log lowlevel debugging information" do
          parsed[:debug] = true
        end

        o.on "--dir DIR", "Change to DIR before starting" do |d|
          parsed[:directory] = d.to_s
          parsed[:worker_directory] = d.to_s
        end

        o.on "-e", "--environment ENVIRONMENT",
             "The environment to run the Rack app on (default development)" do |arg|
          parsed[:environment] = arg
        end

        o.on "-I", "--include PATH", "Specify $LOAD_PATH directories" do |arg|
          $LOAD_PATH.unshift(*arg.split(':'))
        end

        o.on "-p", "--port PORT", "Define the TCP port to bind to",
                                  "Use -b for more advanced options" do |arg|
          parsed[:binds] << "tcp://#{Configuration::DefaultTCPHost}:#{arg}"
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          parsed[:pidfile] = arg
        end

        o.on "--preload", "Preload the app. Cluster mode only" do
          parsed[:preload_app] = true
        end

        o.on "--prune-bundler", "Prune out the bundler env if possible" do
          parsed[:prune_bundler] = true
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          parsed[:quiet] = true
        end

        o.on "-R", "--restart-cmd CMD",
             "The puma command to run during a hot restart",
             "Default: inferred" do |cmd|
          parsed[:restart_cmd] = cmd
        end

        o.on "-S", "--state PATH", "Where to store the state details" do |arg|
          parsed[:state] = arg
        end

        o.on '-t', '--threads INT', "min:max threads to use (default 0:16)" do |arg|
          min, max = arg.split(":")
          if max
            parsed[:min_threads] = min
            parsed[:max_threads] = max
          else
            parsed[:min_threads] = 0
            parsed[:max_threads] = arg
          end
        end

        o.on "--tcp-mode", "Run the app in raw TCP mode instead of HTTP mode" do
          parsed[:mode] = :tcp
        end

        o.on "-V", "--version", "Print the version information" do
          puts "puma version #{Puma::Const::VERSION}"
          exit 1
        end

        o.on "-w", "--workers COUNT",
                   "Activate cluster mode: How many worker processes to create" do |arg|
          parsed[:workers] = arg.to_i
        end

        o.on "--tag NAME", "Additional text to display in process listing" do |arg|
          parsed[:tag] = arg
        end

        o.on '--cli-opts-over-file', 'Use CLI options over config file (default: config file supersedes cli options)' do
          parsed[:cli_opts_over_file] = true
        end

        o.banner = "puma <options> <rackup file>"

        o.on_tail "-h", "--help", "Show help" do
          log o
          exit 1
        end
      end
      parser.parse!(argv)
      parsed
    end

    def write_state
      write_pid

      require 'yaml'

      if path = @options[:state]
        state = { "pid" => Process.pid }

        cfg = @config.dup

        [ :logger, :before_worker_shutdown, :before_worker_boot, :before_worker_fork, :after_worker_boot, :on_restart, :lowlevel_error_handler ].each { |o| cfg.options.delete o }

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

        cur = Process.pid

        at_exit do
          if cur == Process.pid
            delete_pidfile
          end
        end
      end
    end

    def env
      # Try the user option first, then the environment variable,
      # finally default to development
      @options[:environment] || ENV['RACK_ENV'] || 'development'
    end

    def set_rack_environment
      @options[:environment] = env
      ENV['RACK_ENV'] = env
    end

    def delete_pidfile
      if path = @options[:pidfile]
        File.unlink path if File.exist? path
      end
    end

    def find_config
      if @options[:config_file] == '-'
        @options[:config_file] = nil
      else
        @options[:config_file] ||= %W(config/puma/#{env}.rb config/puma.rb).find { |f| File.exist?(f) }
      end
    end

    # :nodoc:
    def parse_options
      find_config
      Puma::Configuration::DSL.load(@options, @options[:config_file])

      parse_argv(@argv).each_pair { |k, v| @options[k] = v }
      @options[:rackup] = @argv.shift if @argv.last

      # prevent Configuration reload from config file
      @options.delete(:config_file) if @options.delete(:cli_opts_over_file)

      @config = Puma::Configuration.new @options

      # Advertise the Configuration
      Puma.cli_config = @config

      @config.load

      if clustered?
        unsupported "worker mode not supported on JRuby or Windows",
                    jruby? || windows?
      end

      if @options[:daemon] and windows?
        unsupported "daemon mode not supported on Windows"
      end
    end

    def clustered?
      @options[:workers] > 0
    end

    def graceful_stop
      @runner.stop_blocked
      log "=== puma shutdown: #{Time.now} ==="
      log "- Goodbye!"
    end

    def generate_restart_data
      # Use the same trick as unicorn, namely favor PWD because
      # it will contain an unresolved symlink, useful for when
      # the pwd is /data/releases/current.
      if dir = ENV['PWD']
        s_env = File.stat(dir)
        s_pwd = File.stat(Dir.pwd)

        if s_env.ino == s_pwd.ino and (jruby? or s_env.dev == s_pwd.dev)
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
        if File.exist?($0)
          arg0 = [Gem.ruby, $0]
        else
          arg0 = [Gem.ruby, "-S", $0]
        end

        # Detect and reinject -Ilib from the command line
        lib = File.expand_path "lib"
        arg0[1,0] = ["-I", lib] if $:[0] == lib

        if defined? Puma::WILD_ARGS
          @restart_argv = arg0 + Puma::WILD_ARGS + ARGV
        else
          @restart_argv = arg0 + ARGV
        end
      end
    end

    def restart_args
      if cmd = @options[:restart_cmd]
        cmd.split(' ') + @original_argv
      else
        @restart_argv
      end
    end

    def jruby_daemon_start
      require 'puma/jruby_restart'
      JRubyRestart.daemon_start(@restart_dir, restart_args)
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

      elsif windows?
        @binder.listeners.each_with_index do |(str,io),i|
          io.close

          # We have to unlink a unix socket path that's not being used
          uri = URI.parse str
          if uri.scheme == "unix"
            path = "#{uri.host}#{uri.path}"
            File.unlink path
          end
        end

        argv = restart_args

        Dir.chdir @restart_dir

        argv += [redirects] unless RUBY_VERSION < '1.9'
        Kernel.exec(*argv)

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

    def prune_bundler?
      @options[:prune_bundler] && clustered? && !@options[:preload_app]
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

      if prune_bundler? && defined?(Bundler)
        puma = Bundler.rubygems.loaded_specs("puma")

        dirs = puma.require_paths.map { |x| File.join(puma.full_gem_path, x) }

        puma_lib_dir = dirs.detect { |x| File.exist? File.join(x, "../bin/puma-wild") }

        deps = puma.runtime_dependencies.map { |d|
          spec = Bundler.rubygems.loaded_specs(d.name)
          "#{d.name}:#{spec.version.to_s}"
        }.join(",")

        if puma_lib_dir
          log "* Pruning Bundler environment"

          home = ENV['GEM_HOME']

          Bundler.with_clean_env do

            ENV['GEM_HOME'] = home

            wild = File.expand_path(File.join(puma_lib_dir, "../bin/puma-wild"))

            wild_loadpath = dirs.join(":")

            args = [Gem.ruby] + [wild, "-I", wild_loadpath, deps] + @original_argv

            Kernel.exec(*args)
          end
        end

        log "! Unable to prune Bundler environment, continuing"
      end

      set_rack_environment

      if clustered?
        @events.formatter = Events::PidFormatter.new
        @options[:logger] = @events

        @runner = Cluster.new(self)
      else
        @runner = Single.new(self)
      end

      setup_signals
      set_process_title

      @status = :run

      @runner.run

      case @status
      when :halt
        log "* Stopping immediately!"
      when :run, :stop
        graceful_stop
      when :restart
        log "* Restarting..."
        @runner.before_restart
        restart!
      when :exit
        # nothing
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
        Signal.trap "SIGUSR1" do
          phased_restart
        end
      rescue Exception
        log "*** SIGUSR1 not implemented, signal based restart unavailable!"
      end

      begin
        Signal.trap "SIGTERM" do
          stop
        end
      rescue Exception
        log "*** SIGTERM not implemented, signal based gracefully stopping unavailable!"
      end

      begin
        Signal.trap "SIGHUP" do
          redirect_io
        end
      rescue Exception
        log "*** SIGHUP not implemented, signal based logs reopening unavailable!"
      end

      if jruby?
        Signal.trap("INT") do
          @status = :exit
          graceful_stop
          exit
        end
      end
    end

    def stop
      @status = :stop
      @runner.stop
    end

    def restart
      @status = :restart
      @runner.restart
    end

    def reload_worker_directory
      @runner.reload_worker_directory if @runner.respond_to?(:reload_worker_directory)
    end

    def phased_restart
      unless @runner.respond_to?(:phased_restart) and @runner.phased_restart
        log "* phased-restart called but not available, restarting normally."
        return restart
      end
      true
    end

    def redirect_io
      @runner.redirect_io
    end

    def stats
      @runner.stats
    end

    def halt
      @status = :halt
      @runner.halt
    end

  private
    def title
      buffer = "puma #{Puma::Const::VERSION} (#{@options[:binds].join(',')})"
      buffer << " [#{@options[:tag]}]" if @options[:tag]
      buffer
    end

    def set_process_title
      Process.respond_to?(:setproctitle) ? Process.setproctitle(title) : $0 = title
    end
  end
end
