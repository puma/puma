# frozen_string_literal: true

require_relative '../plugin'

# Puma's systemd integration allows Puma to inform systemd:
#  1. when it has successfully started
#  2. when it is starting shutdown
#  3. periodically for a liveness check with a watchdog thread
#  4. periodically set the status
Puma::Plugin.create do
  def start(launcher)
    begin
      require 'sd_notify'
    rescue LoadError
      launcher.log_writer.log "Systemd integration failed. It looks like you're trying to use systemd notify but don't have sd_notify gem installed"
      return
    end

    launcher.log_writer.log "* Enabling systemd notification integration"

    # hook_events
    launcher.events.on_booted { SdNotify.ready }
    launcher.events.on_stopped { SdNotify.stopping }
    launcher.events.on_restart { SdNotify.reloading }

    # start watchdog
    if SdNotify.watchdog?
      ping_f = watchdog_sleep_time

      in_background do
        launcher.log_writer.log "Pinging systemd watchdog every #{ping_f.round(1)} sec"
        loop do
          sleep ping_f
          SdNotify.watchdog
        end
      end
    end

    # start status loop
    instance = self
    sleep_time = 1.0
    in_background do
      launcher.log_writer.log "Sending status to systemd every #{sleep_time.round(1)} sec"

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
