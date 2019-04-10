require_relative "helper"

require 'puma/control_cli'

class TestPumaControlCli < Minitest::Test
  def setup
    # use a pipe to get info across thread boundary
    @wait, @ready = IO.pipe
  end

  def wait_booted
    line = @wait.gets until line =~ /Listening on/
  end

  def wait_pid_file(file)
    until File.file?(file) && !File.zero?(file)
      sleep 0.1
    end
  end

  def teardown
    @wait.close
    @ready.close
  end

  def find_open_port
    server = TCPServer.new("127.0.0.1", 0)
    server.addr[1]
  ensure
    server.close
  end

  def test_config_file
    control_cli = Puma::ControlCLI.new ["--config-file", "test/config/state_file_testing_config.rb", "halt"]
    assert_equal "t3-pid", control_cli.instance_variable_get("@pidfile")
  end

  def test_control_url
    host = "127.0.0.1"
    port = find_open_port
    url = "tcp://#{host}:#{port}/"

    opts = [
      "--control-url", url,
      "--control-token", "ctrl",
      "--config-file", "test/config/app.rb",
    ]

    control_cli = Puma::ControlCLI.new (opts + ["start"]), @ready, @ready
    t = Thread.new do
      Thread.current.abort_on_exception = true
      control_cli.run
    end

    wait_booted

    s = TCPSocket.new host, 9292
    s << "GET / HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match "200 OK", body
    assert_match "embedded app", body

    shutdown_cmd = Puma::ControlCLI.new(opts + ["halt"])
    shutdown_cmd.run

    # TODO: assert something about the stop command

    t.join
  end

  def test_status_pid_no_file
    control_cli = Puma::ControlCLI.new ["--config-file", "test/config/app.rb", "status"]

    out, err = capture_subprocess_io do
      assert_raises(SystemExit){control_cli.run}
    end

    assert_match "Neither pid nor control url available", out
  end

  def test_status_pid_running
    pid_file = "/tmp/pidfile.pid"

    File.delete(pid_file) if File.file? pid_file

    opts = [
      "--config-file", "test/config/app.rb",
      "--pidfile", pid_file
    ]

    start_cmd = Puma::ControlCLI.new opts + ["start"], @ready, @ready

    pid = Process.fork do
      start_cmd.run
    end

    wait_pid_file(pid_file)

    status_cmd = Puma::ControlCLI.new opts + ["status"]
    out, err = capture_io {status_cmd.run}

    assert_match "Puma is started", out

    shutdown_cmd = Puma::ControlCLI.new(opts + ["halt"])
    shutdown_cmd.run

    Process.wait(pid)
  end

  def test_status_pid_not_running
    pid_file = "/tmp/pidfile.pid"

    File.delete(pid_file) if File.file? pid_file

    temp_pid = Process.fork {}
    Process.waitpid(temp_pid)

    File.write(pid_file, temp_pid.to_s)

    opts = [
      "--config-file", "test/config/app.rb",
      "--pidfile", pid_file
    ]

    status_cmd = Puma::ControlCLI.new opts + ["status"]
    out, err = capture_subprocess_io do
      assert_raises(SystemExit){status_cmd.run}
    end

    assert_match "Puma is not running", out
  end
end
