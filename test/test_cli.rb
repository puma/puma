require 'test/unit'
require 'puma/cli'
require 'tempfile'

class TestCLI < Test::Unit::TestCase
  def setup
    @pid_file = Tempfile.new("puma-test")
    @pid_path = @pid_file.path
    @pid_file.close!
  end

  def test_pid_file
    cli = Puma::CLI.new ["--pidfile", @pid_path]
    cli.parse_options
    cli.write_pid

    assert_equal File.read(@pid_path).strip.to_i, Process.pid
  end
end
