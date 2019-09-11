# frozen_string_literal: true

require "puma/control_cli"
require "open3"

# Only single mode tests go here. Cluster and pumactl tests
# have their own files, use those instead
class TestIntegration < Minitest::Test
  HOST  = "127.0.0.1"
  TOKEN = "xxyyzz"
  WORKERS = 2

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  def setup
    @ios_to_close = []
  end

  def teardown
    if defined?(@server) && @server
      begin
        Process.kill "INT", @server.pid
      rescue
        Errno::ESRCH
      end
      begin
        Process.wait @server.pid
      rescue Errno::ECHILD
      end
      @server.close unless @server.closed?
      @server = nil
    end

    @ios_to_close.each do |io|
      io.close if io.is_a?(IO) && !io.closed?
      io = nil
    end
  end

  private

  def cli_server(argv, bind = nil)
    if bind
      cmd = "#{BASE} bin/puma -b #{bind} #{argv}"
    else
      @tcp_port = UniquePort.call
      cmd = "#{BASE} bin/puma -b tcp://#{HOST}:#{@tcp_port} #{argv}"
    end
    @server = IO.popen(cmd, "r")
    wait_for_server_to_boot
    @server
  end

  def send_term_to_server(pid)
    Process.kill(:TERM, pid)
    sleep 1
    Process.wait2(pid)
  end

  def restart_server_and_listen(argv)
    cli_server(argv)
    connection = connect
    initial_reply = read_body(connection)
    restart_server(connection)
    [initial_reply, read_body(connect)]
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection)
    Process.kill :USR2, @server.pid
    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
    wait_for_server_to_boot
  end

  def wait_for_server_to_boot
    true while @server.gets !~ /Ctrl-C/ # wait for server to say it booted
  end

  def connect(path = nil)
    s = TCPSocket.new HOST, @tcp_port
    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"
    s
  end

  def read_body(connection)
    Timeout.timeout(10) do
      loop do
        response = connection.readpartial(1024)
        body = response.split("\r\n\r\n", 2).last
        return body if body && !body.empty?
        sleep 0.01
      end
    end
  end

  # gets worker pids from @server output
  def get_worker_pids(phase, size = WORKERS)
    pids = []
    re = /pid: (\d+)\) booted, phase: #{phase}/
    while pids.size < size
      if pid = @server.gets[re, 1]
        pids << pid
      else
        sleep 2
      end
    end
    pids.map(&:to_i)
  end
end
