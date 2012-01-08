require 'optparse'

require 'puma/const'
require 'puma/configuration'

require 'yaml'
require 'uri'

require 'socket'

module Puma
  class ControlCLI

    def initialize(argv, stdout=STDOUT)
      @argv = argv
      @stdout = stdout
    end

    def setup_options
      @parser = OptionParser.new do |o|
        o.on "-S", "--state PATH", "Where the state file to use is" do |arg|
          @path = arg
        end
      end
    end

    def connect
      if str = @config.options[:control_url]
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          return TCPSocket.new uri.host, uri.port
        when "unix"
          path = "#{uri.host}#{uri.path}"
          return UNIXSocket.new path
        else
          raise "Invalid URI: #{str}"
        end
      end

      raise "No status address configured"
    end

    def run
      setup_options

      @parser.parse! @argv

      @state = YAML.load File.read(@path)
      @config = @state['config']

      cmd = @argv.shift

      meth = "command_#{cmd}"

      if respond_to?(meth)
        __send__(meth)
      else
        raise "Unknown command: #{cmd}"
      end
    end

    def request(sock, url)
      token = @config.options[:control_auth_token]
      if token
        url = "#{url}?token=#{token}"
      end

      sock << "GET #{url} HTTP/1.0\r\n\r\n"

      rep = sock.read.split("\r\n")

      m = %r!HTTP/1.\d (\d+)!.match(rep.first)
      if m[1] == "403"
        raise "Unauthorized access to server (wrong auth token)"
      elsif m[1] != "200"
        raise "Bad response code from server: #{m[1]}"
      end

      return rep.last
    end

    def command_pid
      @stdout.puts "#{@state['pid']}"
    end

    def command_stop
      sock = connect
      body = request sock, "/stop"

      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        @stdout.puts "Requested stop from server"
      end
    end

    def command_halt
      sock = connect
      body = request sock, "/halt"

      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        @stdout.puts "Requested halt from server"
      end
    end

    def command_restart
      sock = connect
      body = request sock, "/restart"

      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        @stdout.puts "Requested restart from server"
      end
    end

    def command_stats
      sock = connect
      body = request sock, "/stats"

      @stdout.puts body
    end
  end
end
