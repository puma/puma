require 'puma/runner'

module Puma
  class Cluster < Runner
    def initialize(cli)
      super cli

      @phase = 0
      @workers = []

      @phased_state = :idle
    end

    def stop_workers
      log "- Gracefully shutting down workers..."
      @workers.each { |x| x.term }

      begin
        Process.waitall
      rescue Interrupt
        log "! Cancelled waiting for workers"
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
        @cli.debug "Spawned worker: #{pid}"
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

    def wakeup!
      begin
        @wakeup.write "!" unless @wakeup.closed?
      rescue SystemCallError, IOError
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

      server = Puma::Server.new app, @cli.events
      server.min_threads = min_t
      server.max_threads = max_t
      server.inherit_binder @cli.binder

      unless development?
        server.leak_stack_on_error = false
      end

      Signal.trap "SIGTERM" do
        server.stop
      end

      begin
        @worker_write << "b#{Process.pid}\n"
      rescue SystemCallError, IOError
        STDERR.puts "Master seems to have exitted, exitting."
        return
      end

      server.run.join

    ensure
      @worker_write.close
    end

    def restart
      @restart = true
      @status = :stop
      wakeup!
    end

    def phased_restart
      return false if @options[:preload_app]

      @phased_restart = true
      wakeup!

      true
    end

    def stop
      @status = :stop
      wakeup!
    end

    def stop_blocked
      @status = :stop if @status == :run
      wakeup!
      Process.waitall
    end

    def halt
      @status = :halt
      wakeup!
    end

    def stats
      %Q!{ "workers": #{@workers.size}, "phase": #{@phase} }!
    end

    def run
      @status = :run

      output_header "cluster"

      log "* Process workers: #{@options[:workers]}"

      if @options[:preload_app]
        log "* Preloading application"
        load_and_bind
      else
        log "* Phased restart available"

        unless @cli.config.app_configured?
          error "No application configured, nothing to run"
          exit 1
        end

        @cli.binder.parse @options[:binds], self
      end

      read, @wakeup = Puma::Util.pipe

      Signal.trap "SIGCHLD" do
        wakeup!
      end

      master_pid = Process.pid

      Signal.trap "SIGTERM" do
        # The worker installs their own SIGTERM when booted.
        # Until then, this is run by the worker and the worker
        # should just exit if they get it.
        if Process.pid != master_pid
          log "Early termination of worker"
          exit! 0
        else
          @status = :stop
          wakeup!
        end
      end

      @phased_restart = false

      if @options[:preload_app]
        Signal.trap "SIGUSR1" do
          log "App preloaded, phased restart unavailable"
        end
      else
        Signal.trap "SIGUSR1" do
          phased_restart
        end
      end

      # Used by the workers to detect if the master process dies.
      # If select says that @check_pipe is ready, it's because the
      # master has exited and @suicide_pipe has been automatically
      # closed.
      #
      @check_pipe, @suicide_pipe = Puma::Util.pipe

      if daemon?
        log "* Daemonizing..."
        Process.daemon(true)
      else
        log "Use Ctrl-C to stop"
      end

      @master_pid = Process.pid

      redirect_io

      @cli.write_state

      @master_read, @worker_write = read, @wakeup
      spawn_workers

      Signal.trap "SIGINT" do
        @status = :stop
        wakeup!
      end

      @cli.events.fire_on_booted!

      begin
        while @status == :run
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

            if @phased_restart
              start_phased_restart
              @phased_restart = false
            end

          rescue Interrupt
            @status = :stop
          end
        end

        stop_workers unless @status == :halt
      ensure
        @check_pipe.close
        @suicide_pipe.close
        read.close
        @wakeup.close
      end
    end
  end
end
