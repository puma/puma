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
    @bind_path    = "test/#{name}_server.sock"
  end

  def teardown
    if defined?(@server) && @server && @pid
      stop_server @pid, signal: :INT
    end

    if @ios_to_close
      @ios_to_close.each do |io|
        io.close if io.is_a?(IO) && !io.closed?
        io = nil
      end
    end

    if @bind_path
      refute File.exist?(@bind_path), "Bind path must be removed after stop"
      File.unlink(@bind_path) rescue nil
    end

    # wait until the end for OS buffering?
    if defined?(@server) && @server
      @server.close unless @server.closed?
      @server = nil
    end
  end

  private

  def cli_server(argv, unix: false, config: nil)
    if config
      config_file = Tempfile.new(%w(config .rb))
      config_file.write config
      config_file.close
      config = "-C #{config_file.path}"
    end
    if unix
      cmd = "#{BASE} bin/puma #{config} -b unix://#{@bind_path} #{argv}"
    else
      @tcp_port = UniquePort.call
      cmd = "#{BASE} bin/puma #{config} -b tcp://#{HOST}:#{@tcp_port} #{argv}"
    end
    @server = IO.popen(cmd, "r")
    wait_for_server_to_boot
    @pid = @server.pid
    @server
  end

  # rescue statements are just in case method is called with a server
  # that is already stopped/killed, especially since Process.wait2 is
  # blocking
  def stop_server(pid = @pid, signal: :TERM)
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    begin
      Process.wait2 pid
    rescue Errno::ECHILD
    end
  end

  def restart_server_and_listen(argv)
    cli_server argv
    connection = connect
    initial_reply = read_body(connection)
    restart_server connection
    [initial_reply, read_body(connect)]
  end

  # reuses an existing connection to make sure that works
  def restart_server(connection, log: false)
    Process.kill :USR2, @pid
    connection.write "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
    wait_for_server_to_boot(log: log)
  end

  # wait for server to say it booted
  def wait_for_server_to_boot(log: false)
    if log
      puts "Waiting for server to boot..."
      begin
        line = @server.gets
        puts line if line && line.strip != ''
      end while line !~ /Ctrl-C/
      puts "Server booted!"
    else
      true while @server.gets !~ /Ctrl-C/
    end
  end

  def connect(path = nil, unix: false)
    s = unix ? UNIXSocket.new(@bind_path) : TCPSocket.new(HOST, @tcp_port)
    @ios_to_close << s
    s << "GET /#{path} HTTP/1.1\r\n\r\n"
    true until s.gets == "\r\n"
    s
  end

  def read_body(connection, time_out = 10)
    Timeout.timeout(time_out) do
      loop do
        response = connection.readpartial(1024)
        body = response.split("\r\n\r\n", 2).last
        return body if body && !body.empty?
        sleep 0.01
      end
    end
  end

  # gets worker pids from @server output
  def get_worker_pids(phase = 0, size = WORKERS)
    pids = []
    re = /pid: (\d+)\) booted, phase: #{phase}/
    while pids.size < size
      if pid = @server.gets[re, 1]
        pids << pid
      end
    end
    pids.map(&:to_i)
  end
end
