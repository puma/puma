# frozen_string_literal: true

require 'puma/runner'
require 'puma/detect'
require 'puma/plugin'

module Puma
  # This class is instantiated by the `Puma::Launcher` and used
  # to boot and serve a Ruby application when no puma "workers" are needed
  # i.e. only using "threaded" mode. For example `$ puma -t 1:5`
  #
  # At the core of this class is running an instance of `Puma::Server` which
  # gets created via the `start_server` method from the `Puma::Runner` class
  # that this inherits from.
  class Single < Runner
    def stats
      {
        started_at: @started_at.utc.iso8601,
        backlog: @server.backlog || 0,
        running: @server.running || 0,
        pool_capacity: @server.pool_capacity || 0,
        max_threads: @server.max_threads || 0,
        requests_count: @server.requests_count || 0,
      }
    end

    def restart
      @server.begin_restart
    end

    def stop
      @server.stop(false) if @server
    end

    def halt
      @server.halt
    end

    def stop_blocked
      log "- Gracefully stopping, waiting for requests to finish"
      @control.stop(true) if @control
      @server.stop(true) if @server
    end

    def run
      output_header "single"

      load_and_bind

      Plugins.fire_background

      @launcher.write_state

      start_control

      @server = server = start_server


      log "Use Ctrl-C to stop"
      redirect_io

      @launcher.events.fire_on_booted!

      begin
        server.run.join
      rescue Interrupt
        # Swallow it
      end
    end
  end
end
