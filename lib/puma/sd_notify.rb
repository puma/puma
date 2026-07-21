# frozen_string_literal: true

require "socket"

module Puma
  # The MIT License
  #
  # Copyright (c) 2017-2022 Agis Anastasopoulos
  #
  # Permission is hereby granted, free of charge, to any person obtaining a copy of
  # this software and associated documentation files (the "Software"), to deal in
  # the Software without restriction, including without limitation the rights to
  # use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
  # the Software, and to permit persons to whom the Software is furnished to do so,
  # subject to the following conditions:
  #
  # The above copyright notice and this permission notice shall be included in all
  # copies or substantial portions of the Software.
  #
  # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
  # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
  # FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
  # COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
  # IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
  # CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  #
  # This is a copy of https://github.com/agis/ruby-sdnotify as of commit cca575c
  # The only changes made was "rehoming" it within the Puma module to avoid
  # namespace collisions and applying standard's code formatting style.
  #
  # SdNotify is a pure-Ruby implementation of sd_notify(3). It can be used to
  # notify systemd about state changes. Methods of this package are no-op on
  # non-systemd systems (eg. Darwin).
  #
  # The API maps closely to the original implementation of sd_notify(3),
  # therefore be sure to check the official man pages prior to using SdNotify.
  #
  # @see https://www.freedesktop.org/software/systemd/man/sd_notify.html
  module SdNotify
    # Exception raised when there's an error writing to the notification socket
    class NotifyError < RuntimeError; end

    READY     = "READY=1"
    RELOADING = "RELOADING=1"
    STOPPING  = "STOPPING=1"
    STATUS    = "STATUS="
    ERRNO     = "ERRNO="
    MAINPID   = "MAINPID="
    WATCHDOG  = "WATCHDOG=1"
    FDSTORE   = "FDSTORE=1"
    EXTEND_TIMEOUT_USEC = "EXTEND_TIMEOUT_USEC="

    def self.ready(unset_env=false)
      notify(READY, unset_env)
    end

    def self.reloading(unset_env=false)
      notify(RELOADING, unset_env)
    end

    def self.stopping(unset_env=false)
      notify(STOPPING, unset_env)
    end

    # @param status [String] a custom status string that describes the current
    #   state of the service
    def self.status(status, unset_env=false)
      notify("#{STATUS}#{status}", unset_env)
    end

    # @param errno [Integer]
    def self.errno(errno, unset_env=false)
      notify("#{ERRNO}#{errno}", unset_env)
    end

    # @param pid [Integer]
    def self.mainpid(pid, unset_env=false)
      notify("#{MAINPID}#{pid}", unset_env)
    end

    def self.watchdog(unset_env=false)
      notify(WATCHDOG, unset_env)
    end

    def self.fdstore(unset_env=false)
      notify(FDSTORE, unset_env)
    end

    # @param usec [Integer]
    def self.extend_timeout(usec, unset_env=false)
      notify("#{EXTEND_TIMEOUT_USEC}#{usec}", unset_env)
    end

    def self.extend_timeout_usec
      Integer(ENV["EXTEND_TIMEOUT_USEC"])
    rescue
      0
    end

    def self.extend_timeout_max_usec
      max_usec = ENV["EXTEND_TIMEOUT_MAX_USEC"]
      return extend_timeout_usec if max_usec.nil?

      Integer(max_usec)
    rescue
      0
    end

    # Notify systemd about extended timeout, via the notification socket, if applicable.
    # $EXTEND_TIMEOUT_USEC [Integer] The value specified represents the time in microseconds
    #   for extending the timeout, during which the service must send a new message.
    #
    # @return [Boolean] true if $EXTEND_TIMEOUT_USEC is a valid positive integer, otherwise false
    #
    # @note A service timeout occurs only if the service runtime exceeds the original maximum times specified
    #   by TimeoutStartSec=, RuntimeMaxSec=, and TimeoutStopSec=.
    def self.extend_timeout?
      extend_timeout_usec.positive?
    end

    # @param [Boolean] true if the service manager expects watchdog keep-alive
    #   notification messages to be sent from this process.
    #
    # If the $WATCHDOG_USEC environment variable is set,
    # and the $WATCHDOG_PID variable is unset or set to the PID of the current
    # process
    #
    # @note Unlike sd_watchdog_enabled(3), this method does not mutate the
    #   environment.
    def self.watchdog?
      wd_usec = ENV["WATCHDOG_USEC"]
      wd_pid = ENV["WATCHDOG_PID"]

      return false if !wd_usec

      begin
        wd_usec = Integer(wd_usec)
      rescue
        return false
      end

      return false if wd_usec <= 0
      return true if !wd_pid || wd_pid == $$.to_s

      false
    end

    # Notify systemd with the provided state, via the notification socket, if
    # any.
    #
    # Generally this method will be used indirectly through the other methods
    # of the library.
    #
    # @param state [String]
    # @param unset_env [Boolean]
    #
    # @return [Fixnum, nil] the number of bytes written to the notification
    #   socket or nil if there was no socket to report to (eg. the program wasn't
    #   started by systemd)
    #
    # @raise [NotifyError] if there was an error communicating with the systemd
    #   socket
    #
    # @see https://www.freedesktop.org/software/systemd/man/sd_notify.html
    def self.notify(state, unset_env=false)
      sock = ENV["NOTIFY_SOCKET"]

      return nil if !sock

      ENV.delete("NOTIFY_SOCKET") if unset_env

      begin
        Addrinfo.unix(sock, :DGRAM).connect { |s| s.write state }
      rescue StandardError => e
        raise NotifyError, "#{e.class}: #{e.message}", e.backtrace
      end
    end
  end
end
