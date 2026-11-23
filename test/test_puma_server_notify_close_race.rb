# frozen_string_literal: true

require_relative "helper"
require "puma/events"
require "puma/server"

# Regression tests for puma#3677 — the puma srv thread parks in
# sleep_forever inside IO#close on the @notify pipe when notify_safely
# (e.g. from the worker's SIGTERM trap calling Server#stop) races with
# handle_servers' ensure-block close. notify_safely uses
# `@notify.write_nonblock(msg, exception: false)`, which never waits, so
# IO#close has no in-flight writer to wait for. Both `<<` and `syswrite`
# hang on Ruby < 4.0 when the writer is a signal handler.
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
    skip_unless_signal_exist? USR_SIGNAL

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
    Signal.trap(USR_SIGNAL, "DEFAULT") if Signal.list.key?(USR_SIGNAL)
    server&.stop(true)
  end

  # Deterministic regression test for puma#3677. A signal handler calls
  # notify_safely while the notify pipe is full, so on Ruby < 4.0 a blocking
  # write is guaranteed to still be in flight when another thread closes the
  # pipe, which is what handle_servers' ensure block does. Before the fix,
  # IO#close never returned. Runs in a child process so a hang can be killed.
  def test_close_does_not_hang_while_trap_writes_to_full_notify_pipe
    skip_unless :fork
    skip_unless_signal_exist? USR_SIGNAL

    rd, wr = IO.pipe
    pid = fork do
      rd.close
      server = make_server
      check, notify = IO.pipe
      loop { break if notify.write_nonblock('x' * 4096, exception: false) == :wait_writable }
      loop { break if notify.write_nonblock('x', exception: false) == :wait_writable }
      server.instance_variable_set :@notify, notify

      main = Thread.current
      closer = Thread.new do
        Thread.pass until main.status == 'sleep'
        sleep 0.2 # let the signal handler start its write
        notify.close
        check.close
      end

      Signal.trap(USR_SIGNAL) { server.send(:notify_safely, Puma::Const::STOP_COMMAND) }
      Process.kill USR_SIGNAL, Process.pid
      wr.syswrite(closer.join(5) ? 'closed' : 'hung')
      exit! 0
    end
    wr.close

    assert rd.wait_readable(10), 'child process did not report'
    assert_equal 'closed', rd.read, 'IO#close hung while a trap handler wrote to the notify pipe'
  ensure
    if pid
      Process.kill(:KILL, pid) rescue nil
      Process.wait(pid) rescue nil
    end
    rd&.close
  end

  # notify_safely never blocks. When the notify pipe is full the command is
  # dropped, which is safe because a full pipe already holds a queued command
  # and the server acts on the first one it reads.
  def test_notify_safely_on_full_pipe_drops_command_without_blocking
    server = make_server
    check, notify = IO.pipe
    loop { break if notify.write_nonblock(Puma::Const::STOP_COMMAND * 4096, exception: false) == :wait_writable }
    loop { break if notify.write_nonblock(Puma::Const::STOP_COMMAND, exception: false) == :wait_writable }
    server.instance_variable_set :@check, check
    server.instance_variable_set :@notify, notify

    t0 = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    server.halt
    assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0, :<, 1,
      'notify_safely blocked on a full pipe'

    states = []
    @events.register(:state) { |s| states << s }
    assert server.run.join(10), 'server did not stop on the queued command'
    assert_includes states, :stop, 'server should act on the queued STOP, not the dropped HALT'
    refute_includes @log_writer.stderr.string, 'notify_safely error'
  end

  # Stress test: many cycles of run + concurrent notify_safely + stop.
  # On platforms where MRI's buffered-IO close-vs-write race fires
  # (puma#3677), Server#stop's join would hang inside handle_servers'
  # IO#close. With write_nonblock-based notify_safely, every cycle completes.
  def test_stop_does_not_hang_under_concurrent_notify_safely
    iterations = ENV.fetch("PUMA_STOP_RACE_ITERATIONS", "100").to_i
    deadline = 5.0 # seconds per iteration

    iterations.times do |i|
      server = make_server
      server.run

      writers = Array.new(4) do
        Thread.new do
          loop do
            server.send(:notify_safely, Puma::Const::STOP_COMMAND)
            break if server.shutting_down?
            # write_nonblock does not release the GVL, so without this the
            # writers starve the server thread for a full time slice.
            Thread.pass
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
    log = @log_writer.stderr.string
    refute_includes log, 'notify_safely error:'

    pass
  end
end
