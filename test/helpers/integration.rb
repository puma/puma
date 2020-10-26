# frozen_string_literal: true

require "puma/control_cli"
require "open3"
require_relative 'tmp_path'

# Only single mode tests go here. Cluster and pumactl tests
# have their own files, use those instead
class TestIntegration < Minitest::Test
  include TmpPath
  DARWIN = !!RUBY_PLATFORM[/darwin/]
  HOST  = "127.0.0.1"
  TOKEN = "xxyyzz"

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  def setup
    @ios_to_close = []
    @bind_path    = tmp_path('.sock')
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

  # use only if all socket writes are fast
  # does not wait for a read
  def fast_connect(path = nil, unix: false)
    s = unix ? UNIXSocket.new(@bind_path) : TCPSocket.new(HOST, @tcp_port)
    @ios_to_close << s
    fast_write s, "GET /#{path} HTTP/1.1\r\n\r\n"
    s
  end

  def fast_write(io, str)
    n = 0
    while true
      begin
        n = io.syswrite str
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK => e
        if !IO.select(nil, [io], nil, 5)
          raise e
        end

        retry
      rescue Errno::EPIPE, SystemCallError, IOError => e
        raise e
      end

      return if n == str.bytesize
      str = str.byteslice(n..-1)
    end
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
  def get_worker_pids(phase = 0, size = workers)
    pids = []
    re = /pid: (\d+)\) booted, phase: #{phase}/
    while pids.size < size
      if pid = @server.gets[re, 1]
        pids << pid
      end
    end
    pids.map(&:to_i)
  end

  # used to define correct 'refused' errors
  def thread_run_refused(unix: false)
    if unix
      [Errno::ENOENT, IOError]
    else
      DARWIN ? [Errno::ECONNREFUSED, Errno::EPIPE, EOFError] :
        [Errno::ECONNREFUSED]
    end
  end

  def cli_pumactl(argv, unix: false)
    if unix
      pumactl = IO.popen("#{BASE} bin/pumactl -C unix://#{@control_path} -T #{TOKEN} #{argv}", "r")
    else
      pumactl = IO.popen("#{BASE} bin/pumactl -C tcp://#{HOST}:#{@control_tcp_port} -T #{TOKEN} #{argv}", "r")
    end
    @ios_to_close << pumactl
    Process.wait pumactl.pid
    pumactl
  end

  def hot_restart_does_not_drop_connections(num_threads: 1, total_requests: 500)
    skipped = true
    skip_on :jruby, suffix: <<-MSG
 - file descriptors are not preserved on exec on JRuby; connection reset errors are expected during restarts
    MSG
    skip_on :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'
    skip "Undiagnosed failures on Ruby 2.2" if RUBY_VERSION < '2.3'

    args = "-w #{workers} -t 0:5 -q test/rackup/hello_with_delay.ru"
    if Puma.windows?
      @control_tcp_port = UniquePort.call
      cli_server "#{args} --control-url tcp://#{HOST}:#{@control_tcp_port} --control-token #{TOKEN}"
    else
      cli_server args
    end

    skipped = false
    replies = Hash.new 0
    refused = thread_run_refused unix: false
    message = 'A' * 16_256  # 2^14 - 128

    mutex = Mutex.new
    restart_count = 0
    client_threads = []

    num_requests = (total_requests/num_threads).to_i

    num_threads.times do |thread|
      client_threads << Thread.new do
        num_requests.times do
          begin
            socket = TCPSocket.new HOST, @tcp_port
            fast_write socket, "POST / HTTP/1.1\r\nContent-Length: #{message.bytesize}\r\n\r\n#{message}"
            body = read_body(socket, 10)
            if body == "Hello World"
              mutex.synchronize {
                replies[:success] += 1
                replies[:restart] += 1 if restart_count > 0
              }
            else
              mutex.synchronize { replies[:unexpected_response] += 1 }
            end
          rescue Errno::ECONNRESET, Errno::EBADF
            # connection was accepted but then closed
            # client would see an empty response
            # Errno::EBADF Windows may not be able to make a connection
            mutex.synchronize { replies[:reset] += 1 }
          rescue *refused, IOError
            # IOError intermittently thrown by Ubuntu, add to allow retry
            mutex.synchronize { replies[:refused] += 1 }
          rescue ::Timeout::Error
            mutex.synchronize { replies[:read_timeout] += 1 }
          ensure
            if socket.is_a?(IO) && !socket.closed?
              begin
                socket.close
              rescue Errno::EBADF
              end
            end
          end
        end
#        STDOUT.puts "#{thread} #{replies[:success]}"
      end
    end

    run = true

    restart_thread = Thread.new do
      sleep 0.30  # let some connections in before 1st restart
      while run
        if Puma.windows?
          cli_pumactl 'restart'
        else
          Process.kill :USR2, @pid
        end
        wait_for_server_to_boot
        restart_count += 1
        sleep 1
      end
    end

    client_threads.each(&:join)
    run = false
    restart_thread.join
    if Puma.windows?
      cli_pumactl 'stop'
      Process.wait @server.pid
      @server = nil
    end

    msg = ("   %4d unexpected_response\n"   % replies.fetch(:unexpected_response,0)).dup
    msg << "   %4d refused\n"               % replies.fetch(:refused,0)
    msg << "   %4d read timeout\n"          % replies.fetch(:read_timeout,0)
    msg << "   %4d reset\n"                 % replies.fetch(:reset,0)
    msg << "   %4d success\n"               % replies.fetch(:success,0)
    msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
    msg << "   %4d restart count\n"         % restart_count

    reset = replies[:reset]

    if Puma.windows?
      # 5 is default thread count in Puma?
      reset_max = num_threads * restart_count
      assert_operator reset_max, :>=, reset, "#{msg}Expected reset_max >= reset errors"
    else
      assert_equal 0, reset, "#{msg}Expected no reset errors"
    end
    assert_equal 0, replies[:unexpected_response], "#{msg}Unexpected response"
    assert_equal 0, replies[:refused], "#{msg}Expected no refused connections"
    assert_equal 0, replies[:read_timeout], "#{msg}Expected no read timeouts"

    if Puma.windows?
      assert_equal (num_threads * num_requests) - reset, replies[:success]
    else
      assert_equal (num_threads * num_requests), replies[:success]
    end

  ensure
    return if skipped
    if passed?
      msg = "   restart_count #{restart_count}, reset #{reset}, success after restart #{replies[:restart]}"
      $debugging_info << "#{full_name}\n#{msg}\n"
    else
      $debugging_info << "#{full_name}\n#{msg}\n"
    end
  end
end
