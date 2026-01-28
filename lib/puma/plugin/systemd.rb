# frozen_string_literal: true

require_relative '../plugin'

# Puma's systemd integration allows Puma to inform systemd:
#  1. when it has successfully started
#  2. when it is starting shutdown
#  3. periodically for a liveness check with a watchdog thread
#  4. periodically set the status
Puma::Plugin.create do
  USEC_PER_SEC = 1_000_000.0
  EXTEND_TIMEOUT_BUFFER_SEC = 5.0

  def start(launcher)
    require_relative '../sd_notify'

    launcher.log_writer.log "* Enabling systemd notification integration"

    # hook_events
    if Puma::SdNotify.extend_timeout? &&
        (@extend_timeout_deadline = extend_timeout_deadline(Puma::SdNotify.extend_timeout_max_usec))
      extend_timeout_usec = Puma::SdNotify.extend_timeout_usec
      if extend_timeout_usec < EXTEND_TIMEOUT_BUFFER_SEC * USEC_PER_SEC
        launcher.log_writer.log "WARNING: EXTEND_TIMEOUT_USEC is less than #{EXTEND_TIMEOUT_BUFFER_SEC.to_i} seconds; extending at the configured interval"
      end
      launcher.log_writer.log "Extending the startup by up to #{Puma::SdNotify.extend_timeout_max_usec} usec"

      in_background do
        sleep_time = extend_timeout_sleep_time(extend_timeout_usec)
        launcher.log_writer.log "Extending systemd startup timeout every #{sleep_time.round(1)} sec"
        while @extend_timeout_deadline
          remaining_usec = remaining_extend_timeout_usec(@extend_timeout_deadline)
          break if remaining_usec <= 0

          extension_usec = [extend_timeout_usec, remaining_usec].min
          Puma::SdNotify.extend_timeout(extension_usec)
          sleep sleep_time
        end
      end
    end

    launcher.events.after_booted do
      @extend_timeout_deadline = nil
      Puma::SdNotify.ready
    end
    launcher.events.after_stopped { Puma::SdNotify.stopping }
    launcher.events.before_restart { Puma::SdNotify.reloading }

    # start watchdog
    if Puma::SdNotify.watchdog?
      ping_f = watchdog_sleep_time

      in_background do
        launcher.log_writer.log "Pinging systemd watchdog every #{ping_f.round(1)} sec"
        loop do
          sleep ping_f
          Puma::SdNotify.watchdog
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
        Puma::SdNotify.status(instance.status)
      end
    end
  end

  def status
    if clustered?
      messages = stats[:worker_status].map do |worker|
        common_message(worker[:last_status])
      end.join(',')

      "Puma #{Puma::Const::VERSION}: cluster: #{booted_workers}/#{workers}, worker_status: [#{messages}]"
    else
      "Puma #{Puma::Const::VERSION}: worker: #{common_message(stats)}"
    end
  end

  private

  def extend_timeout_sleep_time(usec)
    sec_f = usec / USEC_PER_SEC
    return sec_f if sec_f <= EXTEND_TIMEOUT_BUFFER_SEC

    sec_f - EXTEND_TIMEOUT_BUFFER_SEC
  end

  def extend_timeout_deadline(usec)
    return nil unless usec.positive?

    monotonic_time + (usec / USEC_PER_SEC)
  end

  def remaining_extend_timeout_usec(deadline)
    ((deadline - monotonic_time) * USEC_PER_SEC).to_i
  end

  def monotonic_time
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def watchdog_sleep_time
    usec = Integer(ENV["WATCHDOG_USEC"])

    sec_f = usec / USEC_PER_SEC
    # "It is recommended that a daemon sends a keep-alive notification message
    # to the service manager every half of the time returned here."
    sec_f / 2
  end

  def stats
    Puma.stats_hash
  end

  def clustered?
    stats.has_key?(:workers)
  end

  def workers
    stats.fetch(:workers, 1)
  end

  def booted_workers
    stats.fetch(:booted_workers, 1)
  end

  def common_message(stats)
    "{ #{stats[:running]}/#{stats[:max_threads]} threads, #{stats[:pool_capacity]} available, #{stats[:backlog]} backlog }"
  end
end
