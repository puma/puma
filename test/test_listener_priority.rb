# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/puma_socket"
require "puma/events"
require "puma/server"

# A server with one thread and three listeners. Requests to a path starting
# with "/block" hold the thread until the test releases them, so the test
# controls what is waiting when the thread frees up.
class TestListenerPriority < PumaTest
  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  HOST = TestPuma::HOST4

  def setup
    @started = Queue.new
    @release = Queue.new
    @ran = Queue.new

    app = ->(env) do
      path = env["PATH_INFO"]
      if path.start_with?("/block")
        @started << path
        @release.pop
      end
      @ran << path
      [200, {}, [path]]
    end

    @server = Puma::Server.new app, nil, { log_writer: Puma::LogWriter.strings, min_threads: 1, max_threads: 1 }
    @server.binder.parse ["tcp://#{HOST}:0", "tcp://#{HOST}:0?priority=100", "tcp://#{HOST}:0?priority=10"]
    @normal_port, @high_port, @medium_port = @server.binder.ios.map { |io| io.addr[1] }
    @server.run
  end

  def teardown
    10.times { @release << true }
    @server.stop(true)
  end

  def test_waiting_requests_run_by_listener_priority
    send_http get("/block"), port: @normal_port
    @started.pop

    send_http get("/normal_1"), port: @normal_port
    wait_for_backlog 1
    send_http get("/medium_1"), port: @medium_port
    wait_for_backlog 2
    send_http get("/high"), port: @high_port
    wait_for_backlog 3
    send_http get("/normal_2"), port: @normal_port
    wait_for_backlog 4
    send_http get("/medium_2"), port: @medium_port
    wait_for_backlog 5

    @release << true

    assert_equal %w[/block /high /medium_1 /medium_2 /normal_1 /normal_2], Array.new(6) { @ran.pop }
  end

  # The priority request isn't complete when the thread first takes it, so it
  # goes to the reactor and comes back to the queue once the rest arrives.
  def test_priority_kept_through_reactor
    send_http get("/block_1"), port: @normal_port
    @started.pop

    priority_socket = new_socket port: @high_port
    priority_socket.write "GET /high HTTP/1.1\r\n"
    wait_for_backlog 1
    send_http get("/block_2"), port: @normal_port
    wait_for_backlog 2
    send_http get("/normal"), port: @normal_port
    wait_for_backlog 3

    @release << true
    @started.pop
    # The thread took the incomplete priority request first and passed it to
    # the reactor, then started /block_2.
    assert_equal 1, @server.backlog

    priority_socket.write "Host: localhost\r\n\r\n"
    wait_for_backlog 2
    @release << true

    assert_equal %w[/block_1 /block_2 /high /normal], Array.new(4) { @ran.pop }
  end

  # A request already in a keep-alive connection's buffer can run on the same
  # thread right away only while other threads are idle. With none idle it
  # goes back in the queue, behind waiting priority work.
  def test_keep_alive_request_waits_behind_priority
    send_http get("/block") + get("/pipelined"), port: @normal_port
    @started.pop

    send_http get("/normal"), port: @normal_port
    wait_for_backlog 1
    send_http get("/high"), port: @high_port
    wait_for_backlog 2

    @release << true

    assert_equal %w[/block /high /normal /pipelined], Array.new(4) { @ran.pop }
  end

  # The same requeue on a priority connection keeps its priority, so the second
  # pipelined request still runs ahead of normal work that was waiting first.
  def test_keep_alive_request_keeps_priority
    send_http get("/block"), port: @normal_port
    @started.pop

    send_http get("/normal"), port: @normal_port
    wait_for_backlog 1
    send_http get("/high_1") + get("/high_2"), port: @high_port
    wait_for_backlog 2

    @release << true

    assert_equal %w[/block /high_1 /high_2 /normal], Array.new(4) { @ran.pop }
  end

  private

  def get(path)
    "GET #{path} HTTP/1.1\r\nHost: localhost\r\n\r\n"
  end

  def wait_for_backlog(size)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    until @server.backlog == size
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        flunk "Backlog stayed at #{@server.backlog}, expected #{size}"
      end
      sleep 0.005
    end
  end
end
