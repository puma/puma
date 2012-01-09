require "rbconfig"
require 'test/unit'
require 'puma/cli'
require 'tempfile'

class TestCLI < Test::Unit::TestCase
  def setup
    @tmp_file = Tempfile.new("puma-test")
    @tmp_path = @tmp_file.path
    @tmp_file.close!

    @tmp_path2 = "#{@tmp_path}2"

    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2
  end

  def teardown
    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2
  end

  def test_pid_file
    cli = Puma::CLI.new ["--pidfile", @tmp_path]
    cli.parse_options
    cli.write_pid

    assert_equal File.read(@tmp_path).strip.to_i, Process.pid
  end

  unless defined?(JRUBY_VERSION) || RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
  def test_control
    url = "unix://#{@tmp_path}"

    sin = StringIO.new
    sout = StringIO.new

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/lobster.ru"], sin, sout
    cli.parse_options

    t = Thread.new { cli.run }

    sleep 1

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read

    assert_equal '{ "backlog": 0, "running": 0 }', body.split("\r\n").last

    cli.stop
    t.join
  end

  def test_control_stop
    url = "unix://#{@tmp_path}"

    sin = StringIO.new
    sout = StringIO.new

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control", url,
                         "--control-token", "",
                         "test/lobster.ru"], sin, sout
    cli.parse_options

    t = Thread.new { cli.run }

    sleep 1

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
end
