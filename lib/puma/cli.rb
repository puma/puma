require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'

module Puma
  class CLI
    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292

    def initialize(argv, stdout=STDOUT, stderr=STDERR)
      @argv = argv
      @stdout = stdout
      @stderr = stderr

      setup_options
    end

    def log(str)
      @stdout.puts str
    end

    def error(str)
      @stderr.puts "ERROR: #{str}"
      exit 1
    end

    def setup_options
      @options = {
        :concurrency => 16
      }

      @binds = []

      @parser = OptionParser.new do |o|
        o.on '-n', '--concurrency INT', "Number of concurrent threads to use" do |arg|
          @options[:concurrency] = arg.to_i
        end

        o.on "-b", "--bind URI", "URI to bind to (tcp:// and unix:// only)" do |arg|
          @binds << arg
        end
      end

      @parser.banner = "puma <options> <rackup file>"

      @parser.on_tail "-h", "--help", "Show help" do
        log @parser
        exit 1
      end
    end

    def load_rackup
      @app, options = Rack::Builder.parse_file @rackup
      @options.merge! options

      options.each do |key,val|
        if key.to_s[0,4] == "bind"
          @binds << val
        end
      end
    end

    def run
      @parser.parse! @argv

      @rackup = ARGV.shift || "config.ru"

      unless File.exists?(@rackup)
        raise "Missing rackup file '#{@rackup}'"
      end

      load_rackup

      if @binds.empty?
        @options[:Host] ||= DefaultTCPHost
        @options[:Port] ||= DefaultTCPPort
      end

      server = Puma::Server.new @app, @options[:concurrency]

      log "Puma #{Puma::Const::PUMA_VERSION} starting..."

      if @options[:Host]
        log "Listening on tcp://#{@options[:Host]}:#{@options[:Port]}"
        server.add_tcp_listener @options[:Host], @options[:Port]
      end

      @binds.each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          log "Listening on #{str}"
          server.add_tcp_listener uri.host, uri.port
        when "unix"
          log "Listening on #{str}"
          path = "#{uri.host}#{uri.path}"

          server.add_unix_listener path
        else
          error "Invalid URI: #{str}"
        end
      end

      log "Use Ctrl-C to stop"

      server.run.join
    end
  end
end
