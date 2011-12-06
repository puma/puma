require 'optparse'

require 'puma/const'
require 'puma/config'

require 'yaml'
require 'uri'

require 'socket'

module Puma
  class ControlCLI

    def initialize(argv)
      @argv = argv
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

      @state = YAML.load_file(@path)
      @config = @state['config']

      cmd = @argv.shift

      meth = "command_#{cmd}"

      if respond_to?(meth)
        __send__(meth)
      else
        raise "Unknown command: #{cmd}"
      end
    end

    def command_pid
      puts "#{@state['pid']}"
    end

    def command_stop
      sock = connect
      sock << "GET /stop HTTP/1.0\r\n\r\n"
      rep = sock.read

      body = rep.split("\r\n").last
      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        puts "Requested stop from server"
      end
    end

    def command_halt
      sock = connect
      s << "GET /halt HTTP/1.0\r\n\r\n"
      rep = s.read

      body = rep.split("\r\n").last
      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        puts "Requested halt from server"
      end
    end

    def command_restart
      sock = connect
      sock << "GET /restart HTTP/1.0\r\n\r\n"
      rep = sock.read

      body = rep.split("\r\n").last
      if body != '{ "status": "ok" }'
        raise "Invalid response: '#{body}'"
      else
        puts "Requested restart from server"
      end
    end

    def command_stats
      sock = connect
      sock << "GET /stats HTTP/1.0\r\n\r\n"
      rep = sock.read

      body = rep.split("\r\n").last

      puts body
    end
  end
end
