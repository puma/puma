# frozen_string_literal: true

require_relative 'sd_notify'

module Puma
  class Systemd
    def initialize(log_writer, events)
      @log_writer = log_writer
      @events = events
    end

    def hook_events
      @events.on_booted { SdNotify.ready }
      @events.on_stopped { SdNotify.stopping }
      @events.on_restart { SdNotify.reloading }
    end

    def start_watchdog
      return unless SdNotify.watchdog?

      ping_f = watchdog_sleep_time

      log "Pinging systemd watchdog every #{ping_f.round(1)} sec"
      Thread.new do
        loop do
          sleep ping_f
          SdNotify.watchdog
        end
      end
    end

    def start_status_loop
      instance = self
      sleep_time = 1.0
      log "Sending status to systemd every #{sleep_time.round(1)} sec"

      Thread.new do
        loop do
          sleep sleep_time
          # TODO: error handling?
          SdNotify.status(instance.status)
        end
      end
    end

    def status
      common = "workers: #{running}/#{max_threads} threads, #{pool_capacity} available, #{backlog} backlog"
      if clustered?
        "Puma #{Puma::Const::VERSION} cluster: #{booted_workers}/#{workers} #{common}"
      else
        "Puma #{Puma::Const::VERSION}: #{common}"
      end
    end

    private

    def watchdog_sleep_time
      usec = Integer(ENV["WATCHDOG_USEC"])

      sec_f = usec / 1_000_000.0
      # "It is recommended that a daemon sends a keep-alive notification message
      # to the service manager every half of the time returned here."
      sec_f / 2
    end

    def log(str)
      @log_writer.log(str)
    end

    def stats
      Puma.stats_hash
    end

    def clustered?
      stats.has_key?('workers')
    end

    def workers
      stats.fetch('workers', 1)
    end

    def booted_workers
      stats.fetch('booted_workers', 1)
    end

    def running
      stats['running']
    end

    def backlog
      stats['backlog']
    end

    def pool_capacity
      stats['pool_capacity']
    end

    def max_threads
      stats['max_threads']
    end
  end
end
