require_relative "helper"

require "puma/cli"

class TestCLI < Minitest::Test
  def setup
    @environment = 'production'
    @tmp_file = Tempfile.new("puma-test")
    @tmp_path = @tmp_file.path
    @tmp_file.close!

    @tmp_path2 = "#{@tmp_path}2"

    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2

    @wait, @ready = IO.pipe

    @events = Puma::Events.strings
    @events.on_booted { @ready << "!" }
  end

  def wait_booted
    @wait.sysread 1
  end

  def teardown
    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2

    @wait.close
    @ready.close
  end

  def test_pid_file
    cli = Puma::CLI.new ["--pidfile", @tmp_path]
    cli.launcher.write_pid

    assert_equal File.read(@tmp_path).strip.to_i, Process.pid
  end

  def test_control_for_tcp
    url = "tcp://127.0.0.1:9877/"
    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:9876",
                         "--control", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new do
      Thread.current.abort_on_exception = true
      cli.run
    end

    wait_booted

    s = TCPSocket.new "127.0.0.1", 9877
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    assert_equal '{ "backlog": 0, "running": 0 }', body.split("\r\n").last

    cli.launcher.stop
    t.join
  end

  unless Puma.jruby? || Puma.windows?
  def test_control_clustered
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "-t", "2:2",
                         "-w", "2",
                         "--control", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }
    t.abort_on_exception = true

    wait_booted

    sleep 2

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read

    require 'json'
    status = JSON.parse(body.split("\n").last)

    assert_equal 2, status["workers"]

    # wait until the first status ping has come through
    sleep 6
    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    assert_match(/\{ "workers": 2, "phase": 0, "booted_workers": 2, "old_workers": 0, "worker_status": \[\{ "pid": \d+, "index": 0, "phase": 0, "booted": true, "last_checkin": "[^"]+", "last_status": \{ "backlog":0, "running":2 \} \},\{ "pid": \d+, "index": 1, "phase": 0, "booted": true, "last_checkin": "[^"]+", "last_status": \{ "backlog":0, "running":2 \} \}\] \}/, body.split("\r\n").last)

    cli.launcher.stop
    t.join
  end

  def test_control
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }
    t.abort_on_exception = true

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read

    assert_equal '{ "backlog": 0, "running": 0 }', body.split("\r\n").last

    cli.launcher.stop
    t.join
  end

  def test_control_stop
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }
    t.abort_on_exception = true

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stop HTTP/1.0\r\n\r\n"
    body = s.read

    assert_equal '{ "status": "ok" }', body.split("\r\n").last

    t.join
  end

  def test_tmp_control
    url = "tcp://127.0.0.1:8232"
    cli = Puma::CLI.new ["--state", @tmp_path, "--control", "auto"]
    cli.launcher.write_state

    data = YAML.load File.read(@tmp_path)

    assert_equal Process.pid, data["pid"]

    url = data["control_url"]

    m = %r!unix://(.*)!.match(url)

    assert m, "'#{url}' is not a URL"
  end

  def test_state_file_callback_filtering
    cli = Puma::CLI.new [ "--config", "test/config/state_file_testing_config.rb",
                          "--state", @tmp_path ]
    cli.launcher.write_state

    data = YAML.load_file(@tmp_path)

    keys_not_stripped = data.keys & Puma::CLI::KEYS_NOT_TO_PERSIST_IN_STATE
    assert_empty keys_not_stripped
  end

  end # JRUBY or Windows

  def test_state
    url = "tcp://127.0.0.1:8232"
    cli = Puma::CLI.new ["--state", @tmp_path, "--control", url]
    cli.launcher.write_state

    data = YAML.load File.read(@tmp_path)

    assert_equal Process.pid, data["pid"]
    assert_equal url, data["control_url"]
  end

  def test_load_path
    cli = Puma::CLI.new ["--include", 'foo/bar']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift

    cli = Puma::CLI.new ["--include", 'foo/bar:baz/qux']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift
    assert_equal 'baz/qux', $LOAD_PATH[0]
    $LOAD_PATH.shift
  end

  def test_environment
    ENV.delete 'RACK_ENV'

    Puma::CLI.new ["--environment", @environment]

    assert_equal ENV['RACK_ENV'], @environment
  end
end
