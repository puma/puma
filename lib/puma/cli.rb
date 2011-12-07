require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'
require 'puma/configuration'

require 'rack/commonlogger'

module Puma
  # Handles invoke a Puma::Server in a command line style.
  #
  class CLI
    IS_JRUBY = defined?(JRUBY_VERSION)

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
      @temp_status_path = nil

      setup_options

      generate_restart_data
    end

    def restart_on_stop!
      if @restart_argv
        @restart = true
        return true
      else
        return false
      end
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

      if defined? Rubinius::OS_ARGV
        @restart_argv = Rubinius::OS_ARGV
      else
        require 'rubygems'

        # if $0 is a file in the current directory, then restart
        # it the same, otherwise add -S on there because it was
        # picked up in PATH.
        #
        if File.exists?($0)
          @restart_argv = [Gem.ruby, $0] + ARGV
        else
          @restart_argv = [Gem.ruby, "-S", $0] + ARGV
        end
      end
    end

    def restart!
      if IS_JRUBY
        require 'puma/jruby_restart'
        JRubyRestart.chdir_exec(@restart_dir, Gem.ruby, *@restart_argv)
      else
        Dir.chdir @restart_dir
        Kernel.exec(*@restart_argv)
      end
    end

    # Write +str+ to +@stdout+
    #
    def log(str)
      @stdout.puts str
    end

    # Write +str+ to +@stderr+
    #
    def error(str)
      @stderr.puts "ERROR: #{str}"
      exit 1
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

    def write_state
      require 'yaml'

      if path = @options[:state]
        state = { "pid" => Process.pid }

        state["config"] = @config

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

      @temp_status_path = @options[:control_path_temp]
    end

    # Parse the options, load the rackup, start the server and wait
    # for it to finish.
    #
    def run
      parse_options

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

      @options[:binds].each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          log "* Listening on #{str}"
          server.add_tcp_listener uri.host, uri.port
        when "unix"
          log "* Listening on #{str}"
          path = "#{uri.host}#{uri.path}"

          server.add_unix_listener path
        else
          error "Invalid URI: #{str}"
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

      log "Use Ctrl-C to stop"

      begin
        server.run.join
      rescue Interrupt
        log " - Gracefully stopping, waiting for requests to finish"
        server.stop(true)
        log " - Goodbye!"
      end

      File.unlink @temp_status_path if @temp_status_path

      if @restart
        log "* Restarting..."
        restart!
      end
    end

    def stop
      @server.stop(true) if @server
    end
  end
end
