require 'puma/cli'
require 'puma/binder'

require 'posix/spawn'

module Puma
  class ClusterCLI < CLI
    def setup_options
      super

      @options[:workers] = 2

      @parser.on "-w", "--workers COUNT",
                 "How many worker processes to create" do |arg|
        @options[:workers] = arg.to_i
      end

      @parser.banner = "puma cluster <options> <rackup file>"
    end

    def parse_options
      @argv.shift if @argv.first == "cluster"
      super
    end

    def worker
      $0 = "puma cluster worker"
      Signal.trap "SIGINT", "IGNORE"

      @suicide_pipe.close

      Thread.new do
        IO.select [@check_pipe]
        log "! Detected parent died, dieing"
        exit! 1
      end

      min_t = @options[:min_threads]
      max_t = @options[:max_threads]

      server = Puma::Server.new @config.app, @events
      server.min_threads = min_t
      server.max_threads = max_t
      server.binder = @binder

      Signal.trap "SIGTERM" do
        server.stop
      end

      server.run.join
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
      @workers = []

      @events = PidEvents.new STDOUT, STDERR

      @options[:logger] = @events

      parse_options

      set_rack_environment

      write_pid
      write_state

      log "Puma #{Puma::Const::PUMA_VERSION} starting in cluster mode..."
      log "* Process workers: #{@options[:workers]}"
      log "* Min threads: #{@options[:min_threads]}, max threads: #{@options[:max_threads]}"
      log "* Environment: #{ENV['RACK_ENV']}"

      @binder.parse @options[:binds], self

      read, write = IO.pipe

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

      begin
        Signal.trap "SIGTERM" do
          stop = true
          write.write "!"
        end
      rescue Exception
      end

      # Used by the workers to detect if the master process dies.
      # If select says that @check_pipe is ready, it's because the
      # master has exited and @suicide_pipe has been automatically
      # closed.
      #
      @check_pipe, @suicide_pipe = IO.pipe

      spawn_workers

      log "* Use Ctrl-C to stop"

      begin
        while !stop
          begin
            IO.select([read], nil, nil, 5)
            check_workers
          rescue Interrupt
            stop = true
          end
        end

        stop_workers
      ensure
        delete_pidfile
      end

      if @restart
        log "* Restarting..."
        restart!
      end
    end
  end
end
