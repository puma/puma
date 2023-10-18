# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

require "puma/cli"
require "json"
require "psych"

class TestCLI < TestPuma::ServerInProcess

  def setup
    @environment = 'production'

    @puma_version_pattern = "\\d+.\\d+.\\d+(\\.[a-z\\d]+)?"
  end

  def control_protocol
    cli_run [HELLO_RU]

    body = send_http_control_read_resp_body 'stats'

    assert_equal Puma.stats_hash, JSON.parse(Puma.stats, symbolize_names: true)

    dmt = Puma::Configuration::DEFAULTS[:max_threads]
    expected_stats = /\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","backlog":0,"running":0,"pool_capacity":#{dmt},"max_threads":#{dmt},"requests_count":0,"versions":\{"puma":"#{@puma_version_pattern}","ruby":\{"engine":"\w+","version":"\d+.\d+.\d+","patchlevel":-?\d+\}\}\}/
    assert_match(expected_stats, body)
  end

  def test_control_for_tcp
    set_control_type :tcp
    control_protocol
  end

  def test_control_for_ssl
    set_control_type :ssl
    control_protocol
  end

  def test_control_clustered
    skip_unless :fork
    set_control_type :unix

    cli_run ["-t", "2:2", "-w", "2", HELLO_RU]

    body = send_http_control_read_resp_body 'stats'

    status = JSON.parse(body)

    assert_equal 2, status["workers"]

    body = send_http_control_read_resp_body 'stats'

    expected_stats = /\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","workers":2,"phase":0,"booted_workers":2,"old_workers":0,"worker_status":\[\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","pid":\d+,"index":0,"phase":0,"booted":true,"last_checkin":"[^"]+","last_status":\{"backlog":0,"running":2,"pool_capacity":2,"max_threads":2,"requests_count":0\}\},\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","pid":\d+,"index":1,"phase":0,"booted":true,"last_checkin":"[^"]+","last_status":\{"backlog":0,"running":2,"pool_capacity":2,"max_threads":2,"requests_count":0\}\}\],"versions":\{"puma":"#{@puma_version_pattern}","ruby":\{"engine":"\w+","version":"\d+.\d+.\d+","patchlevel":-?\d+\}\}\}/
    assert_match(expected_stats, body)
  end

  def test_control
    set_control_type :unix

    cli_run [HELLO_RU]

    body = send_http_control_read_resp_body 'stats'

    dmt = Puma::Configuration::DEFAULTS[:max_threads]
    expected_stats = /{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","backlog":0,"running":0,"pool_capacity":#{dmt},"max_threads":#{dmt},"requests_count":0,"versions":\{"puma":"#{@puma_version_pattern}","ruby":\{"engine":"\w+","version":"\d+.\d+.\d+","patchlevel":-?\d+\}\}\}/
    assert_match(expected_stats, body)
  end

  def test_control_stop
    set_control_type :unix

    cli_run [HELLO_RU]

    body = send_http_control_read_resp_body 'stop'

    assert_equal '{ "status": "ok" }', body
  end

  def test_control_requests_count
    set_control_type :tcp

    cli_run [HELLO_RU]

    body = send_http_control_read_resp_body 'stats'

    assert_equal 0, JSON.parse(body)['requests_count']

    # send real requests to server
    3.times { send_http_read_resp_body GET_10 }

    body = send_http_control_read_resp_body 'stats'

    assert_equal 3, JSON.parse(body)['requests_count']
  end

  def test_control_thread_backtraces
    set_control_type :unix

    cli_run [HELLO_RU]

    if TRUFFLE
      Thread.pass
      sleep 0.2
    end

    # All thread backtraces may be very large, just get a chunk
    socket = send_http_control "thread-backtraces"
    socket.wait_readable 3
    body = socket.sysread 32_768
    assert_match %r{Thread: TID-}, body
  end

  def test_tmp_control
    skip_unless :unix
    skip_if :jruby, suffix: " - Unknown issue"

    cli_run ["--state", state_path, "--control-url", "auto", HELLO_RU]

    opts = @cli.launcher.instance_variable_get(:@options)

    data = Psych.load_file state_path

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

    config_path <<~'CONFIG'
      pidfile 't3-pid'
      workers 3
      on_worker_boot do |index|
        File.open("t3-worker-#{index}-pid", "w") { |f| f.puts Process.pid }
      end

      before_fork { 1 }
      on_worker_shutdown { 1 }
      on_worker_boot { 1 }
      on_worker_fork { 1 }
      on_restart { 1 }
      after_worker_boot { 1 }
      lowlevel_error_handler { 1 }
    CONFIG

    cli_new ["--config", config_path, "--state", state_path]

    @cli.launcher.write_state

    data = Psych.load_file state_path

    assert_equal (Puma::StateFile::ALLOWED_FIELDS & data.keys).sort, data.keys.sort
  end

  def test_log_formatter_default_single
    cli = Puma::CLI.new []
    assert_instance_of Puma::LogWriter::DefaultFormatter, cli.launcher.log_writer.formatter
  end

  def test_log_formatter_default_clustered
    skip_unless :fork

    cli = Puma::CLI.new ["-w 2"]
    assert_instance_of Puma::LogWriter::PidFormatter, cli.launcher.log_writer.formatter
  end

  def log_formatter(ary)
    config_path <<~'CONFIG'
      log_formatter do |str|
        "[#{Process.pid}] [#{Socket.gethostname}] #{Time.now}: #{str}"
      end
    CONFIG
    cli_new (["--config", config_path] + ary)
    assert_instance_of Proc, @cli.launcher.log_writer.formatter
    assert_match(/^\[.*\] \[.*\] .*: test$/, @cli.launcher.log_writer.format('test'))
  end

  def test_log_formatter_custom_single
    log_formatter []
  end

  def test_log_formatter_custom_clustered
    skip_unless :fork
    log_formatter ["-w 2"]
  end

  def test_state
    set_control_type :tcp
    cli_new ["--state", state_path]
    @cli.launcher.write_state

    data = Psych.load_file state_path

    assert_equal Process.pid, data["pid"]
    assert_equal control_uri_str, data["control_url"]
  end

  def test_load_path
    cli_new ["--include", 'foo/bar']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift

    cli_new ["--include", 'foo/bar:baz/qux']

    assert_equal 'foo/bar', $LOAD_PATH[0]
    $LOAD_PATH.shift
    assert_equal 'baz/qux', $LOAD_PATH[0]
    $LOAD_PATH.shift
  end

  def test_extra_runtime_dependencies
    cli_new ['--extra-runtime-dependencies', 'a,b']
    extra_dependencies = @cli.instance_variable_get(:@conf)
                            .instance_variable_get(:@options)[:extra_runtime_dependencies]

    assert_equal %w[a b], extra_dependencies
  end

  def test_environment_app_env
    ENV['RACK_ENV'] = @environment
    ENV['RAILS_ENV'] = @environment
    ENV['APP_ENV'] = 'test'

    cli_new []
    @cli.send :setup_options

    assert_equal 'test', @cli.instance_variable_get(:@conf).environment
  ensure
    ENV.delete 'APP_ENV'
    ENV.delete 'RACK_ENV'
    ENV.delete 'RAILS_ENV'
  end

  def test_environment_rack_env
    ENV['RACK_ENV'] = @environment

    cli_new []
    @cli.send :setup_options

    assert_equal @environment, @cli.instance_variable_get(:@conf).environment
  ensure
    ENV.delete 'RACK_ENV'
  end

  def test_environment_rails_env
    ENV.delete 'RACK_ENV'
    ENV['RAILS_ENV'] = @environment

    cli_new []
    @cli.send :setup_options

    assert_equal @environment, @cli.instance_variable_get(:@conf).environment
  ensure
    ENV.delete 'RAILS_ENV'
  end

  def test_silent
    cli_new ['--silent']
    @cli.send(:setup_options)

    log_writer = @cli.instance_variable_get(:@log_writer)

    assert_equal log_writer.class, Puma::LogWriter.null.class
    assert_equal log_writer.stdout.class, Puma::NullIO
    assert_equal log_writer.stderr, $stderr
  end
end
