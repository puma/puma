require_relative "helper"
require_relative "helpers/ssl" if ::Puma::HAS_SSL
require_relative "helpers/tmp_path"
require_relative "helpers/test_puma/puma_socket"

require "puma/cli"
require "json"
require "psych"

class TestCLI < Minitest::Test
  include SSLHelper if ::Puma::HAS_SSL
  include TmpPath
  include TestPuma::PumaSocket

  def setup
    @environment = 'production'

    @tmp_path = tmp_path('puma-test')
    @tmp_path2 = "#{@tmp_path}2"

    File.unlink @tmp_path  if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2

    @wait, @ready = IO.pipe

    @log_writer = Puma::LogWriter.strings

    @events = Puma::Events.new
    @events.after_booted { @ready << "!" }

    @puma_version_pattern = "\\d+.\\d+.\\d+(\\.[a-z\\d]+)?"
  end

  def wait_booted
    @wait.sysread 1
  rescue Errno::EAGAIN
    sleep 0.001
    retry
  end

  def teardown
    File.unlink @tmp_path if File.exist? @tmp_path
    File.unlink @tmp_path2 if File.exist? @tmp_path2

    @wait.close
    @ready.close
  end

  def check_single_stats(body, check_puma_stats = true)
    http_hash = JSON.parse body

    dmt = Puma::Configuration::DEFAULTS[:max_threads]

    expected_single_root_keys = {
      'started_at' => RE_8601,
      'backlog'    => 0,
      'running'    => 0,
      'pool_capacity'  => dmt,
      'busy_threads'   => 0,
      'max_threads'    => dmt,
      'requests_count' => 0,
      'versions'       => Hash,
    }

    assert_hash expected_single_root_keys, http_hash

    #version keys
    expected_version_hash = {
      'puma' => Puma::Const::VERSION,
      'ruby' => Hash,
    }
    assert_hash expected_version_hash, http_hash['versions']

    #version ruby keys
    expected_version_ruby_hash = {
      'engine'     => RUBY_ENGINE,
      'version'    => RUBY_VERSION,
      'patchlevel' => RUBY_PATCHLEVEL,
    }

    assert_hash expected_version_ruby_hash, http_hash['versions']['ruby']

    if check_puma_stats
      puma_stats_hash = JSON.parse(Puma.stats)
      assert_hash expected_single_root_keys, puma_stats_hash
      assert_hash expected_version_hash, puma_stats_hash['versions']
      assert_hash expected_version_ruby_hash, puma_stats_hash['versions']['ruby']

      assert_equal Puma.stats_hash, JSON.parse(Puma.stats, symbolize_names: true)
    end
  end

  def test_control_for_tcp
    control_port = UniquePort.call
    url = "tcp://127.0.0.1:#{control_port}/"

    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:0",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    body = send_http_read_resp_body "GET /stats HTTP/1.0\r\n\r\n", port: control_port

    check_single_stats body

  ensure
    cli.launcher.stop
    t.join
  end

  def test_control_for_ssl
    skip_unless :ssl

    require "net/http"
    control_port = UniquePort.call
    control_host = "127.0.0.1"
    control_url = "ssl://#{control_host}:#{control_port}?#{ssl_query}"
    token = "token"

    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:0",
                         "--control-url", control_url,
                         "--control-token", token,
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    body = send_http_read_resp_body "GET /stats?token=#{token} HTTP/1.0\r\n\r\n",
      port: control_port, ctx: new_ctx

    check_single_stats body
  ensure
    # always called, even if skipped
    cli&.launcher&.stop
    t&.join
  end

  def test_control_for_unix
    skip_unless :unix
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    body = send_http_read_resp_body "GET /stats HTTP/1.0\r\n\r\n", path: @tmp_path

    check_single_stats body
  ensure
    if UNIX_SKT_EXIST
      cli.launcher.stop
      t.join
    end
  end

  def test_control_stop
    skip_unless :unix
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    body = send_http_read_resp_body "GET /stop HTTP/1.0\r\n\r\n", path: @tmp_path

    assert_equal '{ "status": "ok" }', body
  ensure
    t.join if UNIX_SKT_EXIST
  end

  def test_control_requests_count
    @bind_port = UniquePort.call
    control_port = UniquePort.call
    url = "tcp://127.0.0.1:#{control_port}/"

    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:#{@bind_port}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    body = send_http_read_resp_body "GET /stats HTTP/1.0\r\n\r\n", port: control_port

    assert_equal 0, JSON.parse(body)['requests_count']

    # send real requests to server
    3.times { send_http_read_resp_body GET_10 }

    body = send_http_read_resp_body "GET /stats HTTP/1.0\r\n\r\n", port: control_port

    assert_equal 3, JSON.parse(body)['requests_count']
  ensure
    cli.launcher.stop
    t.join
  end

  def test_control_thread_backtraces
    skip_unless :unix
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/hello.ru"], @log_writer, @events

    t = Thread.new { cli.run }

    wait_booted

    if TRUFFLE
      Thread.pass
      sleep 0.2
    end

    # All thread backtraces may be very large, just get a chunk
    socket = send_http "GET /thread-backtraces HTTP/1.0\r\n\r\n", path: @tmp_path
    socket.wait_readable 3
    body = socket.sysread 32_768
    assert_match %r{Thread: TID-}, body
  ensure
    cli.launcher.stop if cli
    t.join if UNIX_SKT_EXIST
  end


  def test_tmp_control
    skip_if :jruby, suffix: " - Unknown issue"

    cli = Puma::CLI.new ["--state", @tmp_path, "--control-url", "auto"]
    cli.launcher.write_state

    opts = cli.launcher.instance_variable_get(:@options)

    data = Psych.load_file @tmp_path

    Puma::StateFile::ALLOWED_FIELDS.each do |key|
      val =
        case key
        when 'pid'          then Process.pid
        when 'running_from' then File.expand_path('.') # same as Launcher
        else                     opts[key.to_sym]
        end
      assert_equal val, data[key]
    end

    assert_equal (Puma::StateFile::ALLOWED_FIELDS & data.keys).sort, data.keys.sort

    url = data["control_url"]

    assert_operator url, :start_with?, "unix://", "'#{url}' is not a URL"
  end

  def test_state_file_callback_filtering
    skip_unless :fork
    cli = Puma::CLI.new [ "--config", "test/config/state_file_testing_config.rb",
                          "--state", @tmp_path ]
    cli.launcher.write_state

    data = Psych.load_file @tmp_path

    assert_equal (Puma::StateFile::ALLOWED_FIELDS & data.keys).sort, data.keys.sort
  end

  def test_log_formatter_default_single
    cli = Puma::CLI.new [ ]
    assert_instance_of Puma::LogWriter::DefaultFormatter, cli.launcher.log_writer.formatter
  end

  def test_log_formatter_default_clustered
    skip_unless :fork

    cli = Puma::CLI.new [ "-w 2" ]
    assert_instance_of Puma::LogWriter::PidFormatter, cli.launcher.log_writer.formatter
  end

  def test_log_formatter_custom_single
    cli = Puma::CLI.new [ "--config", "test/config/custom_log_formatter.rb" ]
    assert_instance_of Proc, cli.launcher.log_writer.formatter
    assert_match(/^\[.*\] \[.*\] .*: test$/, cli.launcher.log_writer.format('test'))
  end

  def test_log_formatter_custom_clustered
    skip_unless :fork

    cli = Puma::CLI.new [ "--config", "test/config/custom_log_formatter.rb", "-w 2" ]
    assert_instance_of Proc, cli.launcher.log_writer.formatter
    assert_match(/^\[.*\] \[.*\] .*: test$/, cli.launcher.log_writer.format('test'))
  end

  def test_state
    url = "tcp://127.0.0.1:#{UniquePort.call}"
    cli = Puma::CLI.new ["--state", @tmp_path, "--control-url", url]
    cli.launcher.write_state

    data = Psych.load_file @tmp_path

    assert_equal Process.pid, data["pid"]
    assert_equal url, data["control_url"]
  end

  def test_load_path
    Puma::CLI.new ["--include", 'foo/bar']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift

    Puma::CLI.new ["--include", 'foo/bar:baz/qux']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift
    assert_equal 'baz/qux', $LOAD_PATH[0]
    $LOAD_PATH.shift
  end

  def test_extra_runtime_dependencies
    cli = Puma::CLI.new ['--extra-runtime-dependencies', 'a,b']
    extra_dependencies = cli.instance_variable_get(:@conf)
                            .instance_variable_get(:@options)[:extra_runtime_dependencies]

    assert_equal %w[a b], extra_dependencies
  end

  def test_environment_app_env
    ENV['RACK_ENV'] = @environment
    ENV['RAILS_ENV'] = @environment
    ENV['APP_ENV'] = 'test'

    cli = Puma::CLI.new []
    cli.send(:setup_options)

    assert_equal 'test', cli.instance_variable_get(:@conf).environment
  ensure
    ENV.delete 'APP_ENV'
    ENV.delete 'RAILS_ENV'
  end

  def test_environment_rack_env
    ENV['RACK_ENV'] = @environment

    cli = Puma::CLI.new []
    cli.send(:setup_options)

    assert_equal @environment, cli.instance_variable_get(:@conf).environment
  end

  def test_environment_rails_env
    ENV.delete 'RACK_ENV'
    ENV['RAILS_ENV'] = @environment

    cli = Puma::CLI.new []
    cli.send(:setup_options)

    assert_equal @environment, cli.instance_variable_get(:@conf).environment
  ensure
    ENV.delete 'RAILS_ENV'
  end

  def test_silent
    cli = Puma::CLI.new ['--silent']
    cli.send(:setup_options)

    log_writer = cli.instance_variable_get(:@log_writer)

    assert_equal log_writer.class, Puma::LogWriter.null.class
    assert_equal log_writer.stdout.class, Puma::NullIO
    assert_equal log_writer.stderr, $stderr
  end

  def test_plugins
    assert_empty Puma::Plugins.instance_variable_get(:@plugins)

    cli = Puma::CLI.new ['--plugin', 'tmp_restart', '--plugin', 'systemd']
    cli.send(:setup_options)

    assert Puma::Plugins.find("tmp_restart")
    assert Puma::Plugins.find("systemd")
  end
end
