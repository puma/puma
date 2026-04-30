# frozen_string_literal: true

require_relative "helper"
require "puma/events"
require "puma/server"

# Regression tests for puma#3677 — the puma srv thread parks in
# sleep_forever inside IO#close on the @notify pipe when notify_safely
# (e.g. from the worker's SIGTERM trap calling Server#stop) races with
# handle_servers' ensure-block close. The fix replaces `@notify << msg`
# (buffered IO, holds Ruby's IO write lock that close also wants) with
# `@notify.syswrite(msg)` (single write(2) syscall, lock-free).
class TestPumaServerNotifyCloseRace < PumaTest
  USR_SIGNAL = "USR1"

  def setup
    @app = ->(_env) { [200, {}, ["ok"]] }
    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
  end

  def make_server
    server = Puma::Server.new @app, @events,
      log_writer: @log_writer, min_threads: 1, max_threads: 1
    server.add_tcp_listener "127.0.0.1", 0
    server
  end

  # Trap-context safety: notify_safely must be callable from a signal
  # handler. Puma's launcher signal handlers (TERM/USR2/INT/HUP) all
  # invoke it via Server#stop / #begin_restart. A regression that uses
  # Mutex#synchronize would raise ThreadError here.
  def test_notify_safely_callable_from_trap_context
    skip_unless_signal_exist? USR_SIGNAL if respond_to?(:skip_unless_signal_exist?)

    server = make_server
    server.run

    error = nil
    done = Queue.new
    Signal.trap(USR_SIGNAL) do
      begin
        server.send(:notify_safely, Puma::Const::STOP_COMMAND)
      rescue => e
        error = e
      end
      done << true
    end

    Process.kill(USR_SIGNAL, Process.pid)
    assert_equal true, done.pop, "trap handler did not run"
    assert_nil error,
      "notify_safely raised in trap context: #{error&.class}: #{error&.message}"

    # The puma srv thread reads STOP_COMMAND off @check; give it a moment.
    deadline = Time.now + 2
    sleep 0.01 until server.shutting_down? || Time.now > deadline
    assert_predicate server, :shutting_down?,
      "STOP_COMMAND was not delivered through @notify"
  ensure
    Signal.trap(USR_SIGNAL, "DEFAULT")
    server&.stop(true)
  end

  # Stress test: many cycles of run + concurrent notify_safely + stop.
  # On platforms where MRI's buffered-IO close-vs-write race fires
  # (puma#3677), Server#stop's join would hang inside handle_servers'
  # IO#close. With syswrite-based notify_safely, every cycle completes.
  def test_stop_does_not_hang_under_concurrent_notify_safely
    iterations = ENV.fetch("PUMA_STOP_RACE_ITERATIONS", "100").to_i
    deadline = 5.0 # seconds per iteration

    iterations.times do |i|
      server = make_server
      server.run

      writers = 4.times.map do
        Thread.new do
          loop do
            server.send(:notify_safely, Puma::Const::STOP_COMMAND)
            break if server.shutting_down?
          end
        end
      end

      stopper = Thread.new { server.stop(true) }
      finished = stopper.join(deadline)
      if finished.nil?
        bt = (server.thread&.backtrace || []).first(10).join("\n  ")
        stopper.kill
        writers.each(&:kill)
        flunk "Server#stop hung after #{deadline}s on iteration #{i}.\n" \
              "puma srv backtrace:\n  #{bt}"
      end
      writers.each(&:join)
    end

    pass
  end
end
