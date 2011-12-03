require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'

require 'rack/commonlogger'

module Puma
  # Handles invoke a Puma::Server in a command line style.
  #
  class CLI
    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292

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

      setup_options
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
        :quiet => false
      }

      @binds = []

      @parser = OptionParser.new do |o|
        o.on "-b", "--bind URI", "URI to bind to (tcp:// and unix:// only)" do |arg|
          @binds << arg
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          @options[:pidfile] = arg
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          @options[:quiet] = true
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

    # Load the specified rackup file, pull an options from
    # the rackup file, and set @app.
    #
    def load_rackup
      @app, options = Rack::Builder.parse_file @rackup
      @options.merge! options

      options.each do |key,val|
        if key.to_s[0,4] == "bind"
          @binds << val
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
      end
    end

    # :nodoc:
    def parse_options
      @parser.parse! @argv
    end

    # Parse the options, load the rackup, start the server and wait
    # for it to finish.
    #
    def run
      parse_options

      @rackup = ARGV.shift || "config.ru"

      unless File.exists?(@rackup)
        raise "Missing rackup file '#{@rackup}'"
      end

      load_rackup
      write_pid

      unless @options[:quiet]
        @app = Rack::CommonLogger.new(@app, STDOUT)
      end

      if @binds.empty?
        @options[:Host] ||= DefaultTCPHost
        @options[:Port] ||= DefaultTCPPort
      end

      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      server = Puma::Server.new @app, @events
      server.min_threads = min_t
      server.max_threads = max_t

      log "Puma #{Puma::Const::PUMA_VERSION} starting..."
      log "* Min threads: #{min_t}, max threads: #{max_t}"

      if @options[:Host]
        log "* Listening on tcp://#{@options[:Host]}:#{@options[:Port]}"
        server.add_tcp_listener @options[:Host], @options[:Port]
      end

      @binds.each do |str|
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

      log "Use Ctrl-C to stop"

      begin
        server.run.join
      rescue Interrupt
        log " - Shutting down..."
      end
    end
  end
end
