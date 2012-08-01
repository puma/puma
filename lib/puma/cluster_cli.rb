require 'puma/cli'
require 'posix/spawn'

module Puma
  class ClusterCLI < CLI
    def setup_options
      @options = {
        :workers => 2,
        :min_threads => 0,
        :max_threads => 16,
        :quiet => false,
        :binds => []
      }

      @parser = OptionParser.new do |o|
        o.on "-w", "--workers COUNT",
             "How many worker processes to create" do |arg|
          @options[:workers] = arg.to_i
        end

        o.on "-b", "--bind URI",
             "URI to bind to (tcp://, unix://, ssl://)" do |arg|
          @options[:binds] << arg
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
    end

    class PidEvents < Events
      def log(str)
        super "[#{$$}] #{str}"
      end

      def write(str)
        super "[#{$$}] #{str}"
      end

      def error(str)
        super "[#{$$}] #{str}"
      end
    end

    def worker
      Signal.trap "SIGINT", "IGNORE"

      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      server = Puma::Server.new @config.app, @events
      server.min_threads = min_t
      server.max_threads = max_t

      @ios.each do |fd, uri|
        server.inherit_tcp_listener uri.host, uri.port, fd
      end

      Signal.trap "SIGTERM" do
        server.stop
      end

      server.run.join
    end

    def stop_workers
      @workers.each { |x| x.term }
    end

    class Worker
      def initialize(pid)
        @pid = pid
      end

      attr_reader :pid

      def term
        begin
          Process.kill "TERM", @pid
        rescue Errno::ESRCH
        end
      end
    end

    def spawn_workers
      diff = @options[:workers] - @workers.size

      diff.times do
        pid = fork { worker }
        debug "Spawned worker: #{pid}"
        @workers << Worker.new(pid)
      end
    end

    def check_workers
      while true
        pid = Process.waitpid(-1, Process::WNOHANG)
        break unless pid

        @workers.delete_if { |w| w.pid == pid }
      end

      spawn_workers
    end

    def run
      @debug = true

      @workers = []
      @events = PidEvents.new STDOUT, STDERR

      @options[:logger] = @events

      parse_options

      set_rack_environment

      @ios = []

      @options[:binds].each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          s = TCPServer.new(uri.host, uri.port)
          s.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)
          s.setsockopt(Socket::SOL_SOCKET,Socket::SO_REUSEADDR, true)
          s.listen 1024

          @ios << [s, uri]
        else
          raise "bad bind uri - #{str}"
        end
      end

      log "Puma #{Puma::Const::PUMA_VERSION} starting in cluster mode..."
      log "* Process workers: #{@options[:workers]}"
      log "* Min threads: #{@options[:min_threads]}, max threads: #{@options[:max_threads]}"
      log "* Environment: #{ENV['RACK_ENV']}"

      read, write = IO.pipe

      Signal.trap "SIGCHLD" do
        write.write "!"
      end

      spawn_workers

      begin
        while true
          IO.select([read], nil, nil, 5)
          check_workers
        end
      rescue Interrupt
        stop_workers
        p Process.waitall
      end
    end
  end
end
