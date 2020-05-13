# frozen_string_literal: true

require 'puma/events'

module Puma
  class Systemd
    def initialize(events)
      @events = events
    end

    def start_watchdog
      usec = Integer(ENV["WATCHDOG_USEC"])
      return warn "systemd Watchdog too fast: #{usec}" if usec < 1_000_000

      sec_f = usec / 1_000_000.0
      # "It is recommended that a daemon sends a keep-alive notification message
      # to the service manager every half of the time returned here."
      ping_f = sec_f / 2
      log "Pinging systemd watchdog every #{ping_f.round(1)} sec"
      Thread.new do
        loop do
          sleep ping_f
          SdNotify.watchdog
        end
      end
    end

    def log(str)
      @events.log str
    end
  end
end
