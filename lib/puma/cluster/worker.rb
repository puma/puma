# frozen_string_literal: true

module Puma
  class Cluster < Puma::Runner
    #—————————————————————— DO NOT USE — this class is for internal use only ———


    # This class is instantiated by the `Puma::Cluster` and represents a single
    # worker process.
    #
    # At the core of this class is running an instance of `Puma::Server` which
    # gets created via the `start_server` method from the `Puma::Runner` class
    # that this inherits from.
    class Worker < Puma::Runner # :nodoc:
      attr_reader :index, :master

      def initialize(index:, master:, launcher:, pipes:, app: nil)
        super(launcher)

        @index = index
        @master = master
        @check_pipe = pipes[:check_pipe]
        @worker_write = pipes[:worker_write]
        @fork_pipe = pipes[:fork_pipe]
        @wakeup = pipes[:wakeup]
        @app = app
        @server = nil
        @hook_data = {}
        @worker_pids = []
      end

      def run
        title  = "puma: cluster worker #{index}: #{master}"
        title += " [#{@options[:tag]}]" if @options[:tag] && !@options[:tag].empty?
        $0 = title

        Signal.trap "SIGINT", "IGNORE"
        Signal.trap "SIGCHLD", "DEFAULT"

        Thread.new do
          Puma.set_thread_name "wrkr check"
          @check_pipe.wait_readable
          log "! Detected parent died, dying"
          exit! 1
        end

        # If we're not running under a Bundler context, then
        # report the info about the context we will be using
        if !ENV['BUNDLE_GEMFILE']
          if File.exist?("Gemfile")
            log "+ Gemfile in context: #{File.expand_path("Gemfile")}"
          elsif File.exist?("gems.rb")
            log "+ Gemfile in context: #{File.expand_path("gems.rb")}"
          end
        end

        # Invoke any worker boot hooks so they can get
        # things in shape before booting the app.
        @config.run_hooks(:before_worker_boot, index, @log_writer, @hook_data)

        begin
          @server = start_server
        rescue Exception => e
          log "! Unable to start worker"
          log e
          log e.backtrace.join("\n    ")
          exit 1
        end

        restart_server = Queue.new << true << false

        fork_worker = @options[:fork_worker] && index == 0

        if fork_worker
          restart_server.clear
          trap_sigchld

          Thread.new do
            Puma.set_thread_name "wrkr fork"
            while (idx = @fork_pipe.gets)
              idx = idx.to_i
              if idx == -1 # stop server
                if restart_server.length > 0
                  restart_server.clear
                  @server.begin_restart(true)
                  @config.run_hooks(:before_refork, nil, @log_writer, @hook_data)
                end
              elsif idx == -2 # refork cycle is done
                @config.run_hooks(:after_refork, nil, @log_writer, @hook_data)
              elsif idx == 0 # restart server
                restart_server << true << false
              else # fork worker
                pid = spawn_worker(idx)
                @worker_write << "#{PIPE_FORK}#{pid}:#{idx}\n" rescue nil
              end
            end
          end
        end

        mold = false

        if @options[:mold_worker]
          Signal.trap "SIGURG" do
            mold = true
            restart_server.clear
            @server.begin_restart
            restart_server << false
          end
        end

        Signal.trap "SIGTERM" do
          @worker_write << "#{PIPE_EXTERNAL_TERM}#{Process.pid}\n" rescue nil
          restart_server.clear
          @server.stop
          restart_server << false
        end

        begin
          @worker_write << "#{PIPE_BOOT}#{Process.pid}:#{index}\n"
        rescue SystemCallError, IOError
          STDERR.puts "Master seems to have exited, exiting."
          return
        end

        while restart_server.pop
          server_thread = @server.run
          # A promotion received before the server was running had no effect.
          @server.begin_restart if mold

          if @log_writer.debug? && index == 0
            debug_loaded_extensions "Loaded Extensions - worker 0:"
          end

          start_stat_thread
          server_thread.join
        end

        if mold
          run_mold
        else
          # Invoke any worker shutdown hooks so they can prevent the worker
          # exiting until any background operations are completed
          @config.run_hooks(:before_worker_shutdown, index, @log_writer, @hook_data)
        end
      ensure
        @worker_write << "#{PIPE_TERM}#{Process.pid}\n" rescue nil
        @worker_write.close
      end

      private

      def start_stat_thread
        @stat_thread ||= Thread.new(@worker_write) do |io|
          Puma.set_thread_name "stat pld"
          base_payload = "#{PIPE_PING}#{Process.pid}"

          while true
            begin
              payload = base_payload.dup

              hsh = @server.stats
              hsh.each do |k, v|
                payload << %Q! "#{k}":#{v || 0},!
              end
              # sub call properly adds 'closing' string
              io << payload.sub(/,\z/, " }\n")
              @server.reset_max
            rescue SystemCallError, IOError
              break
            end
            sleep @options[:worker_check_interval]
          end
        end
      end

      def run_mold
        $0 = $0.sub("cluster worker", "mold")

        stopping = false
        stop_read, stop_write = Puma::Util.pipe
        Signal.trap "SIGTERM" do
          @worker_write << "#{PIPE_EXTERNAL_TERM}#{Process.pid}\n" rescue nil
          stopping = true
          stop_write.write_nonblock(".", exception: false)
        end

        trap_sigchld

        @config.run_hooks(:after_mold_promotion, index, @log_writer, @hook_data)
        start_stat_thread
        @worker_write << "#{PIPE_MOLD}#{Process.pid}\n"

        loop do
          IO.select([@fork_pipe, stop_read])
          # A retired mold must not read indices meant for its replacement.
          break if stopping

          idx = @fork_pipe.sysread(MOLD_FORK_BYTES).unpack1(MOLD_FORK_FORMAT)
          pid = spawn_worker(idx)
          @worker_write << "#{PIPE_FORK}#{pid}:#{idx}\n"
        rescue EOFError
          break
        end

        @config.run_hooks(:before_mold_shutdown, index, @log_writer, @hook_data)
      end

      def trap_sigchld
        Signal.trap "SIGCHLD" do
          wakeup! if @worker_pids.reject! do |p|
            Process.wait(p, Process::WNOHANG) rescue true
          end
        end
      end

      def spawn_worker(idx)
        @config.run_hooks(:before_worker_fork, idx, @log_writer, @hook_data)

        pipes = { check_pipe: @check_pipe, worker_write: @worker_write }
        if @options[:mold_worker]
          pipes[:fork_pipe] = @fork_pipe
          pipes[:wakeup] = @wakeup
        end

        pid = fork do
          new_worker = Worker.new index: idx,
                                  master: master,
                                  launcher: @launcher,
                                  pipes: pipes,
                                  app: @app
          new_worker.run
        end

        if !pid
          log "! Complete inability to spawn new workers detected"
          log "! Seppuku is the only choice."
          exit! 1
        end

        @worker_pids << pid
        @config.run_hooks(:after_worker_fork, idx, @log_writer, @hook_data)
        pid
      end
    end
  end
end
