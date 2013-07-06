require 'puma/runner'

module Puma
  class Single < Runner
    def stats
      b = @server.backlog
      r = @server.running
      %Q!{ "backlog": #{b}, "running": #{r} }!
    end

    def restart
      @server.begin_restart
    end

    def stop
      @server.stop false
    end

    def halt
      @server.halt
    end

    def stop_blocked
      log "- Gracefully stopping, waiting for requests to finish"
      @server.stop(true)
    end

    def jruby_daemon?
      daemon? and @cli.jruby?
    end

    def run
      already_daemon = false

      if jruby_daemon?
        require 'puma/jruby_restart'

        if JRubyRestart.daemon?
          # load and bind before redirecting IO so errors show up on stdout/stderr
          load_and_bind
        end

        already_daemon = JRubyRestart.daemon_init
      end

      output_header "single"

      if jruby_daemon?
        unless already_daemon
          pid = nil

          Signal.trap "SIGUSR2" do
            log "* Started new process #{pid} as daemon..."
            exit
          end

          pid = @cli.jruby_daemon_start
          sleep
        end
      else
        load_and_bind
        if daemon?
          log "* Daemonizing..."
          Process.daemon(true)
        end
      end

      @cli.write_state

      server = Puma::Server.new @app, @cli.events
      server.binder = @cli.binder
      server.min_threads = @options[:min_threads]
      server.max_threads = @options[:max_threads]

      unless development?
        server.leak_stack_on_error = false
      end

      @server = server

      unless @options[:daemon]
        log "Use Ctrl-C to stop"
      end

      redirect_io

      @cli.events.fire_on_booted!

      begin
        server.run.join
      rescue Interrupt
        # Swallow it
      end
    end
  end
end
