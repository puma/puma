require 'puma/runner'

module Puma
  class Cluster < Runner
    def initialize(cli)
      super cli

      @phase = 0
      @workers = []
      @next_check = nil

      @phased_state = :idle
      @phased_restart = false
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

      # Be sure to change the directory again before loading
      # the app. This way we can pick up new code.
      if dir = @options[:worker_directory]
        log "+ Changing to #{dir}"
        Dir.chdir dir
      end
    end

    class Worker
      def initialize(idx, pid, phase)
        @index = idx
        @pid = pid
        @phase = phase
        @stage = :started
        @signal = "TERM"
        @last_checkin = Time.now
      end

      attr_reader :index, :pid, :phase, :signal, :last_checkin

      def booted?
        @stage == :booted
      end

      def boot!
        @last_checkin = Time.now
        @stage = :booted
      end

      def ping!
        @last_checkin = Time.now
      end

      def ping_timeout?(which)
        Time.now - @last_checkin > which
      end

      def term
        begin
          if @first_term_sent && (Time.new - @first_term_sent) > 30
            @signal = "KILL"
          else
            @first_term_sent ||= Time.new
          end

          Process.kill @signal, @pid
        rescue Errno::ESRCH
        end
      end

      def kill
        Process.kill "KILL", @pid
      rescue Errno::ESRCH
      end
    end

    def spawn_workers
      diff = @options[:workers] - @workers.size

      master = Process.pid

      diff.times do
        idx = next_worker_index

        pid = fork { worker(idx, master) }
        @cli.debug "Spawned worker: #{pid}"
        @workers << Worker.new(idx, pid, @phase)
        @options[:after_worker_boot].each { |h| h.call }
      end

      if diff > 0
        @phased_state = :idle
      end
    end

    def next_worker_index
      all_positions =  0...@options[:workers] 
      occupied_positions = @workers.map { |w| w.index }
      available_positions = all_positions.to_a - occupied_positions 
      available_positions.first
    end

    def all_workers_booted?
      @workers.count { |w| !w.booted? } == 0
    end

    def check_workers
      return if @next_check && @next_check >= Time.now

      @next_check = Time.now + 5

      any = false

      @workers.each do |w|
        if w.ping_timeout?(@options[:worker_timeout])
          log "! Terminating timed out worker: #{w.pid}"
          w.kill
          any = true
        end
      end

      # If we killed any timed out workers, try to catch them
      # during this loop by giving the kernel time to kill them.
      sleep 1 if any

      while @workers.any?
        pid = Process.waitpid(-1, Process::WNOHANG)
        break unless pid

        @workers.delete_if { |w| w.pid == pid }
      end

      spawn_workers

      if all_workers_booted?
        # If we're running at proper capacity, check to see if
        # we need to phase any workers out (which will restart
        # in the right phase).
        #
        w = @workers.find { |x| x.phase != @phase }

        if w
          if @phased_state == :idle
            @phased_state = :waiting
            log "- Stopping #{w.pid} for phased upgrade..."
          end

          w.term
          log "- #{w.signal} sent to #{w.pid}..."
        end
      end
    end

    def wakeup!
      begin
        @wakeup.write "!" unless @wakeup.closed?
      rescue SystemCallError, IOError
      end
    end

    def worker(index, master)
      $0 = "puma: cluster worker #{index}: #{master}"
      Signal.trap "SIGINT", "IGNORE"

      @master_read.close
      @suicide_pipe.close

      Thread.new do
        IO.select [@check_pipe]
        log "! Detected parent died, dying"
        exit! 1
      end

      # If we're not running under a Bundler context, then
      # report the info about the context we will be using
      if !ENV['BUNDLER_GEMFILE'] and File.exist?("Gemfile")
        log "+ Gemfile in context: #{File.expand_path("Gemfile")}"
      end

      # Invoke any worker boot hooks so they can get
      # things in shape before booting the app.
      hooks = @options[:before_worker_boot]
      hooks.each { |h| h.call(index) }

      server = start_server

      Signal.trap "SIGTERM" do
        server.stop
      end

      begin
        @worker_write << "b#{Process.pid}\n"
      rescue SystemCallError, IOError
        STDERR.puts "Master seems to have exitted, exitting."
        return
      end

      Thread.new(@worker_write) do |io|
        payload = "p#{Process.pid}\n"

        while true
          sleep 5
          io << payload
        end
      end

      server.run.join

    ensure
      @worker_write.close
    end

    def restart
      @restart = true
      stop
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
      @control.stop(true) if @control
      Process.waitall
    end

    def halt
      @status = :halt
      wakeup!
    end

    def stats
      %Q!{ "workers": #{@workers.size}, "phase": #{@phase}, "booted_workers": #{@workers.count{|w| w.booted?}} }!
    end

    def preload?
      @options[:preload_app]
    end

    def run
      @status = :run

      output_header "cluster"

      log "* Process workers: #{@options[:workers]}"

      if preload?
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

      Signal.trap "TTIN" do
        @options[:workers] += 1
        wakeup!
      end

      Signal.trap "TTOU" do
        @options[:workers] -= 1 if @options[:workers] >= 2
        @workers.last.term
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
          stop
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

      redirect_io

      start_control

      @cli.write_state

      @master_read, @worker_write = read, @wakeup
      spawn_workers

      Signal.trap "SIGINT" do
        stop
      end

      @cli.events.fire_on_booted!

      begin
        while @status == :run
          begin
            res = IO.select([read], nil, nil, 5)

            if res
              req = read.read_nonblock(1)

              next if !req || req == "!"

              pid = read.gets.to_i

              if w = @workers.find { |x| x.pid == pid }
                case req
                when "b"
                  w.boot!
                  log "- Worker #{w.index} (pid: #{pid}) booted, phase: #{w.phase}"
                when "p"
                  w.ping!
                end
              else
                log "! Out-of-sync worker list, no #{pid} worker"
              end
            end

            if @phased_restart
              start_phased_restart
              @phased_restart = false
            end

            check_workers

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
