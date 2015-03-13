require "rbconfig"
require 'test/unit'
require 'puma/cli'
require 'tempfile'

class TestCLI < Test::Unit::TestCase
  def setup
    @environment = 'production'
    @tmp_file = Tempfile.new("puma-test")
    @tmp_path = @tmp_file.path
    @tmp_file.close!

    @tmp_path2 = "#{@tmp_path}2"

    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2

    @wait, @ready = IO.pipe

    @events = Events.strings
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
    cli.parse_options
    cli.write_pid

    assert_equal File.read(@tmp_path).strip.to_i, Process.pid
  end

  def test_control_for_tcp
    url = "tcp://127.0.0.1:9877/"
    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:9876",
                         "--control", url,
                         "--control-token", "",
                         "test/lobster.ru"], @events

    cli.parse_options

    thread_exception = nil
    t = Thread.new do
      begin
        cli.run
      rescue Exception => e
        thread_exception = e
      end
    end

    wait_booted

    s = TCPSocket.new "127.0.0.1", 9877
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    assert_equal '{ "backlog": 0, "running": 0 }', body.split("\r\n").last

    cli.stop
    t.join
    assert_equal nil, thread_exception
  end

  unless defined?(JRUBY_VERSION) || RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
  def test_control
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/lobster.ru"], @events
    cli.parse_options

    t = Thread.new { cli.run }

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read

    assert_equal '{ "backlog": 0, "running": 0 }', body.split("\r\n").last

    cli.stop
    t.join
  end

  def test_control_stop
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/lobster.ru"], @events
    cli.parse_options

    t = Thread.new { cli.run }

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
    cli.parse_options
    cli.write_state

    data = YAML.load File.read(@tmp_path)

    assert_equal Process.pid, data["pid"]

    url = data["config"].options[:control_url]

    m = %r!unix://(.*)!.match(url)

    assert m, "'#{url}' is not a URL"
  end
  end # JRUBY or Windows

  def test_state
    url = "tcp://127.0.0.1:8232"
    cli = Puma::CLI.new ["--state", @tmp_path, "--control", url]
    cli.parse_options
    cli.write_state

    data = YAML.load File.read(@tmp_path)

    assert_equal Process.pid, data["pid"]
    assert_equal url, data["config"].options[:control_url]
  end

  def test_load_path
    cli = Puma::CLI.new ["--include", 'foo/bar']
    cli.parse_options

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift

    cli = Puma::CLI.new ["--include", 'foo/bar:baz/qux']
    cli.parse_options

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift
    assert_equal 'baz/qux', $LOAD_PATH[0]
    $LOAD_PATH.shift
  end

  def test_environment
    cli = Puma::CLI.new ["--environment", @environment]
    cli.parse_options
    cli.set_rack_environment

    assert_equal ENV['RACK_ENV'], @environment
  end

  def test_default
    cli = Puma::CLI.new []
    cli.parse_options

    assert_equal 0, cli.options[:min_threads]
    assert_equal 16, cli.options[:max_threads]
  end

  def test_threads
    cli = Puma::CLI.new ['-t', '1']
    cli.parse_options

    assert_equal 0, cli.options[:min_threads]
    assert_equal '1', cli.options[:max_threads]
  end

  def test_dsl_over_cli
    cli = Puma::CLI.new ['-t', '2:3', '-C', 'test/config/puma.rb']
    cli.parse_options

    assert_equal 1, cli.options[:min_threads]
    assert_equal 2, cli.options[:max_threads]
  end

  def test_cli_over_dsl
    cli = Puma::CLI.new ['--cli-opts-over-file', '-t', '2:3', '-C', 'test/config/puma.rb']
    cli.parse_options

    assert_equal '2', cli.options[:min_threads]
    assert_equal '3', cli.options[:max_threads]

    assert_equal %w(tcp://0.0.0.0:9292), cli.options[:binds]
  end

  def test_binds_concat
    cli = Puma::CLI.new ['-b', 'tcp://0.0.0.0:9080', '-b', 'tcp://0.0.0.0:9081', '-C', 'test/config/puma.rb']
    cli.parse_options

    expected = %w(
      tcp://0.0.0.0:9080
      tcp://0.0.0.0:9081
      tcp://0.0.0.0:9290
      tcp://0.0.0.0:9291
    )

    assert_equal expected.sort, cli.options[:binds].sort
  end

  def test_binds_replace
    cli = Puma::CLI.new ['--cli-opts-over-file', '-b', 'tcp://0.0.0.0:9080', '-b', 'tcp://0.0.0.0:9081', '-C', 'test/config/puma.rb']
    cli.parse_options

    expected = %w(
      tcp://0.0.0.0:9080
      tcp://0.0.0.0:9081
    )

    assert_equal expected.sort, cli.options[:binds].sort
  end
end
