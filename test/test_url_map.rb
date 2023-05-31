require_relative "helper"
require_relative "helpers/integration"

class TestURLMap < TestIntegration
  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    super
  end

  # make sure the mapping defined in url_map_test/config.ru works
  def test_basic_url_mapping
    skip_unless_signal_exist? :USR2

    @tcp_port = UniquePort.call
    timeout = 1
    env = {
      "BUNDLE_GEMFILE" => File.join(File.expand_path("url_map_test/Gemfile", __dir__))
    }
    cmd = "bundle exec puma -q -w 1 --prune-bundler -b tcp://#{HOST}:#{@tcp_port}"
    Dir.chdir(File.expand_path("url_map_test", __dir__)) do
      @server = IO.popen(env, cmd.split, "r")
    end
    wait_for_server_to_boot
    @pid = @server.pid
    connection = connect("/ok")
    # Puma 6.2.2 and below will time out here with Ruby v3.3
    # see https://github.com/puma/puma/pull/3165
    initial_reply = read_body(connection, timeout)
    assert_match("OK", initial_reply)
  end
end
