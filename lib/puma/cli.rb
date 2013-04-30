require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'
require 'puma/configuration'
require 'puma/binder'
require 'puma/detect'
require 'puma/daemon_ext'
require 'puma/util'

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

      @phase = 0
      @workers = []

      @events = Events.new @stdout, @stderr

      @server = nil
      @status = nil

      @restart = false
      @phased_state = :idle

      @io_redirected = false


      ENV['NEWRELIC_DISPATCHER'] ||= "puma"

      setup_options

      generate_restart_data

      @binder = Binder.new(@events)
      @binder.import_from_env
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

    def restart!
      @options[:on_restart].each do |blk|
        blk.call self
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
        JRubyRestart.chdir_exec(@restart_dir, @restart_argv)
      else
        redirects = {}
        @binder.listeners.each_with_index do |(l,io),i|
          ENV["PUMA_INHERIT_#{i}"] = "#{io.to_i}:#{l}"
          redirects[io.to_i] = io.to_i
        end

        if cmd = @options[:restart_cmd]
          argv = cmd.split(' ') + @original_argv
        else
          argv = @restart_argv
        end

        Dir.chdir @restart_dir

        argv += [redirects] unless RUBY_VERSION < '1.9'
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

      env = @options[:environment] ||
                   ENV['RACK_ENV'] ||
                     'development'

      @options[:environment] = env
      ENV['RACK_ENV'] = env
    end

    def delete_pidfile
      if path = @options[:pidfile]
        File.unlink path
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

    def graceful_stop(server)
      log " - Gracefully stopping, waiting for requests to finish"
      @status.stop(true) if @status
      server.stop(true)
      delete_pidfile
      log " - Goodbye!"
    end

    def redirect_io
      stdout = @options[:redirect_stdout]
      stderr = @options[:redirect_stderr]
      append = @options[:redirect_append]

      if stdout
        @io_redirected = true
        STDOUT.reopen stdout, (append ? "a" : "w")
        STDOUT.sync = true
        STDOUT.puts "=== puma startup: #{Time.now} ==="
      end

      if stderr
        STDERR.reopen stderr, (append ? "a" : "w")
        STDERR.sync = true
        STDERR.puts "=== puma startup: #{Time.now} ==="
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
        run_cluster
      else
        run_single
      end
    end

    def run_single
      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      log "Puma #{Puma::Const::PUMA_VERSION} starting..."
      log "* Min threads: #{min_t}, max threads: #{max_t}"
      log "* Environment: #{ENV['RACK_ENV']}"

      @binder.parse @options[:binds], self

      if @options[:daemon]
        Process.daemon(true, @io_redirected)
      end

      write_state

      server = Puma::Server.new @config.app, @events
      server.binder = @binder
      server.min_threads = min_t
      server.max_threads = max_t

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

      unless @options[:daemon]
        log "Use Ctrl-C to stop"
      end

      redirect_io

      if jruby?
        Signal.trap("INT") do
          graceful_stop server
          exit
        end
      end

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

    def worker(upgrade)
      $0 = "puma: cluster worker: #{@master_pid}"
      Signal.trap "SIGINT", "IGNORE"

      @master_read.close
      @suicide_pipe.close

      Thread.new do
        IO.select [@check_pipe]
        log "! Detected parent died, dying"
        exit! 1
      end

      # Be sure to change the directory again before loading
      # the app. This way we can pick up new code.
      if upgrade
        if dir = @options[:worker_directory]
          log "+ Changing to #{dir}"
          Dir.chdir dir
        end
      end

      # Invoke any worker boot hooks so they can get
      # things in shape before booting the app.
      hooks = @options[:worker_boot]
      hooks.each { |h| h.call }

      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      server = Puma::Server.new @config.app, @events
      server.min_threads = min_t
      server.max_threads = max_t
      server.inherit_binder @binder

      Signal.trap "SIGTERM" do
        server.stop
      end

      @worker_write << "b#{Process.pid}\n"

      server.run.join

    ensure
      @worker_write.close
    end

    def stop_workers
      log "- Gracefully shutting down workers..."
      @workers.each { |x| x.term }

      begin
        Process.waitall
      rescue Interrupt
        log "! Cancelled waiting for workers"
      else
        log "- Goodbye!"
      end
    end

    def start_phased_restart
      @phase += 1
      log "- Starting phased worker restart, phase: #{@phase}"
    end

    class Worker
      def initialize(pid, phase)
        @pid = pid
        @phase = phase
        @stage = :started
      end

      attr_reader :pid, :phase

      def booted?
        @stage == :booted
      end

      def boot!
        @stage = :booted
      end

      def term
        begin
          Process.kill "TERM", @pid
        rescue Errno::ESRCH
        end
      end
    end

    def spawn_workers
      diff = @options[:workers] - @workers.size

      upgrade = (@phased_state == :waiting)

      diff.times do
        pid = fork { worker(upgrade) }
        debug "Spawned worker: #{pid}"
        @workers << Worker.new(pid, @phase)
      end

      if diff > 0
        @phased_state = :idle
      end
    end

    def all_workers_booted?
      @workers.count { |w| !w.booted? } == 0
    end

    def check_workers
      while @workers.any?
        pid = Process.waitpid(-1, Process::WNOHANG)
        break unless pid

        @workers.delete_if { |w| w.pid == pid }
      end

      spawn_workers

      if @phased_state == :idle && all_workers_booted?
        # If we're running at proper capacity, check to see if
        # we need to phase any workers out (which will restart
        # in the right phase).
        #
        w = @workers.find { |x| x.phase != @phase }

        if w
          @phased_state = :waiting
          log "- Stopping #{w.pid} for phased upgrade..."
          w.term
        end
      end
    end

    def run_cluster
      log "Puma #{Puma::Const::PUMA_VERSION} starting in cluster mode..."
      log "* Process workers: #{@options[:workers]}"
      log "* Min threads: #{@options[:min_threads]}, max threads: #{@options[:max_threads]}"
      log "* Environment: #{ENV['RACK_ENV']}"

      @binder.parse @options[:binds], self

      read, write = Puma::Util.pipe

      Signal.trap "SIGCHLD" do
        write.write "!"
      end

      stop = false

      begin
        Signal.trap "SIGUSR2" do
          @restart = true
          stop = true
          write.write "!"
        end
      rescue Exception
      end

      master_pid = Process.pid

      begin
        Signal.trap "SIGTERM" do
          # The worker installs there own SIGTERM when booted.
          # Until then, this is run by the worker and the worker
          # should just exit if they get it.
          if Process.pid != master_pid
            log "Early termination of worker"
            exit! 0
          else
            stop = true
            write.write "!"
          end
        end
      rescue Exception
      end

      phased_restart = false

      begin
        Signal.trap "SIGUSR1" do
          phased_restart = true
          write.write "!"
        end
      rescue Exception
      end

      # Used by the workers to detect if the master process dies.
      # If select says that @check_pipe is ready, it's because the
      # master has exited and @suicide_pipe has been automatically
      # closed.
      #
      @check_pipe, @suicide_pipe = Puma::Util.pipe

      if @options[:daemon]
        Process.daemon(true, @io_redirected)
      else
        log "Use Ctrl-C to stop"
      end

      @master_pid = Process.pid

      redirect_io

      write_state

      @master_read, @worker_write = read, write
      spawn_workers

      Signal.trap "SIGINT" do
        stop = true
        write.write "!"
      end

      begin
        while !stop
          begin
            res = IO.select([read], nil, nil, 5)

            if res
              req = read.read_nonblock(1)

              if req == "b"
                pid = read.gets.to_i
                w = @workers.find { |x| x.pid == pid }
                if w
                  w.boot!
                  log "- Worker #{pid} booted, phase: #{w.phase}"
                else
                  log "! Out-of-sync worker list, no #{pid} worker"
                end
              end
            end

            check_workers

            if phased_restart
              start_phased_restart
              phased_restart = false
            end

          rescue Interrupt
            stop = true
          end
        end

        stop_workers
      ensure
        delete_pidfile
        @check_pipe.close
        @suicide_pipe.close
        read.close
        write.close
      end

      if @restart
        log "* Restarting..."
        restart!
      end
    end

    def stop
      @status.stop(true) if @status
      @server.stop(true) if @server
      delete_pidfile
    end
  end
end
