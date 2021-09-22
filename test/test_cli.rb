require_relative "helper"
require_relative "helpers/ssl" if ::Puma::HAS_SSL
require_relative "helpers/tmp_path"

require "puma/cli"
require "json"

class TestCLI < Minitest::Test
  include SSLHelper if ::Puma::HAS_SSL
  include TmpPath

  def setup
    @environment = 'production'

    @tmp_path = tmp_path('puma-test')
    @tmp_path2 = "#{@tmp_path}2"

    File.unlink @tmp_path  if File.exist? @tmp_path
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

  def test_control_for_tcp
    cntl = UniquePort.call
    url = "tcp://127.0.0.1:#{cntl}/"

    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:0",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new do
      cli.run
    end

    wait_booted

    s = TCPSocket.new "127.0.0.1", cntl
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_equal Puma.stats_hash, JSON.parse(Puma.stats, symbolize_names: true)

    dmt = Puma::Configuration.new.default_max_threads
    assert_match(/{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","backlog":0,"running":0,"pool_capacity":#{dmt},"max_threads":#{dmt},"requests_count":0}/, body.split(/\r?\n/).last)

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
                         "test/rackup/lobster.ru"], @events

    t = Thread.new do
      cli.run
    end

    wait_booted

    body = ""
    http = Net::HTTP.new control_host, control_port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE
    http.start do
      req = Net::HTTP::Get.new "/stats?token=#{token}", {}
      body = http.request(req).body
    end

    dmt = Puma::Configuration.new.default_max_threads
    expected_stats = /{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","backlog":0,"running":0,"pool_capacity":#{dmt},"max_threads":#{dmt}/
    assert_match(expected_stats, body.split(/\r?\n/).last)

  ensure
    cli.launcher.stop if cli
    t.join if t
  end

  def test_control_clustered
    skip_unless :fork
    skip_unless :unix
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "-t", "2:2",
                         "-w", "2",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    # without this, Minitest.after_run will trigger on this test ?
    $debugging_hold = true

    t = Thread.new { cli.run }

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    require 'json'
    status = JSON.parse(body.split("\n").last)

    assert_equal 2, status["workers"]

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_match(/\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","workers":2,"phase":0,"booted_workers":2,"old_workers":0,"worker_status":\[\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","pid":\d+,"index":0,"phase":0,"booted":true,"last_checkin":"[^"]+","last_status":\{"backlog":0,"running":2,"pool_capacity":2,"max_threads":2,"requests_count":0\}\},\{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","pid":\d+,"index":1,"phase":0,"booted":true,"last_checkin":"[^"]+","last_status":\{"backlog":0,"running":2,"pool_capacity":2,"max_threads":2,"requests_count":0\}\}\]\}/, body.split("\r\n").last)
  ensure
    if UNIX_SKT_EXIST && HAS_FORK
      cli.launcher.stop
      t.join

      done = nil
      until done
        @events.stdout.rewind
        log = @events.stdout.readlines.join ''
        done = log[/ - Goodbye!/]
      end

      $debugging_hold = false
    end
  end

  def test_control
    skip_unless :unix
    url = "unix://#{@tmp_path}"

    cli = Puma::CLI.new ["-b", "unix://#{@tmp_path2}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    dmt = Puma::Configuration.new.default_max_threads
    assert_match(/{"started_at":"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z","backlog":0,"running":0,"pool_capacity":#{dmt},"max_threads":#{dmt},"requests_count":0}/, body.split("\r\n").last)
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
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /stop HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_equal '{ "status": "ok" }', body.split("\r\n").last
  ensure
    t.join if UNIX_SKT_EXIST
  end

  def test_control_requests_count
    tcp  = UniquePort.call
    cntl = UniquePort.call
    url = "tcp://127.0.0.1:#{cntl}/"

    cli = Puma::CLI.new ["-b", "tcp://127.0.0.1:#{tcp}",
                         "--control-url", url,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new do
      cli.run
    end

    wait_booted

    s = TCPSocket.new "127.0.0.1", cntl
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_equal 0, JSON.parse(body.split(/\r?\n/).last)['requests_count']

    # send real requests to server
    3.times do
      s = TCPSocket.new "127.0.0.1", tcp
      s << "GET / HTTP/1.0\r\n\r\n"
      body = s.read
      s.close
    end

    s = TCPSocket.new "127.0.0.1", cntl
    s << "GET /stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_equal 3, JSON.parse(body.split(/\r?\n/).last)['requests_count']
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
                         "test/rackup/lobster.ru"], @events

    t = Thread.new { cli.run }

    wait_booted

    s = UNIXSocket.new @tmp_path
    s << "GET /thread-backtraces HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    assert_match %r{Thread: TID-}, body.split("\r\n").last
  ensure
    cli.launcher.stop if cli
    t.join if UNIX_SKT_EXIST
  end

  def control_gc_stats(uri, cntl)
    cli = Puma::CLI.new ["-b", uri,
                         "--control-url", cntl,
                         "--control-token", "",
                         "test/rackup/lobster.ru"], @events

    t = Thread.new do
      cli.run
    end

    wait_booted

    s = yield
    s << "GET /gc-stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    lines = body.split("\r\n")
    json_line = lines.detect { |l| l[0] == "{" }
    pairs = json_line.scan(/\"[^\"]+\": [^,]+/)
    gc_stats = {}
    pairs.each do |p|
      p =~ /\"([^\"]+)\": ([^,]+)/ || raise("Can't parse #{p.inspect}!")
      gc_stats[$1] = $2
    end
    gc_count_before = gc_stats["count"].to_i

    s = yield
    s << "GET /gc HTTP/1.0\r\n\r\n"
    body = s.read # Ignored
    s.close

    s = yield
    s << "GET /gc-stats HTTP/1.0\r\n\r\n"
    body = s.read
    s.close

    lines = body.split("\r\n")
    json_line = lines.detect { |l| l[0] == "{" }
    gc_stats = JSON.parse(json_line)
    gc_count_after = gc_stats["count"].to_i

    # Hitting the /gc route should increment the count by 1
    assert(gc_count_before < gc_count_after, "make sure a gc has happened")

  ensure
    cli.launcher.stop if cli
    t.join
  end

  def test_control_gc_stats_tcp
    uri  = "tcp://127.0.0.1:#{UniquePort.call}/"
    cntl_port = UniquePort.call
    cntl = "tcp://127.0.0.1:#{cntl_port}/"

    control_gc_stats(uri, cntl) { TCPSocket.new "127.0.0.1", cntl_port }
  end

  def test_control_gc_stats_unix
    skip_unless :unix

    uri  = "unix://#{@tmp_path2}"
    cntl = "unix://#{@tmp_path}"

    control_gc_stats(uri, cntl) { UNIXSocket.new @tmp_path }
  end

  def test_tmp_control
    skip_if :jruby, suffix: " - Unknown issue"

    cli = Puma::CLI.new ["--state", @tmp_path, "--control-url", "auto"]
    cli.launcher.write_state

    data = YAML.load File.read(@tmp_path)

    assert_equal Process.pid, data["pid"]

    url = data["control_url"]

    m = %r!unix://(.*)!.match(url)

    assert m, "'#{url}' is not a URL"
  end

  def test_state_file_callback_filtering
    skip_unless :fork
    cli = Puma::CLI.new [ "--config", "test/config/state_file_testing_config.rb",
                          "--state", @tmp_path ]
    cli.launcher.write_state

    data = YAML.load_file(@tmp_path)

    keys_not_stripped = data.keys & Puma::CLI::KEYS_NOT_TO_PERSIST_IN_STATE
    assert_empty keys_not_stripped
  end

  def test_log_formatter_default_single
    cli = Puma::CLI.new [ ]
    assert_instance_of Puma::Events::DefaultFormatter, cli.launcher.events.formatter
  end

  def test_log_formatter_default_clustered
    skip_unless :fork

    cli = Puma::CLI.new [ "-w 2" ]
    assert_instance_of Puma::Events::PidFormatter, cli.launcher.events.formatter
  end

  def test_log_formatter_custom_single
    cli = Puma::CLI.new [ "--config", "test/config/custom_log_formatter.rb" ]
    assert_instance_of Proc, cli.launcher.events.formatter
    assert_match(/^\[.*\] \[.*\] .*: test$/, cli.launcher.events.format('test'))
  end

  def test_log_formatter_custom_clustered
    skip_unless :fork

    cli = Puma::CLI.new [ "--config", "test/config/custom_log_formatter.rb", "-w 2" ]
    assert_instance_of Proc, cli.launcher.events.formatter
    assert_match(/^\[.*\] \[.*\] .*: test$/, cli.launcher.events.format('test'))
  end

  def test_state
    url = "tcp://127.0.0.1:#{UniquePort.call}"
    cli = Puma::CLI.new ["--state", @tmp_path, "--control-url", url]
    cli.launcher.write_state

    data = YAML.load File.read(@tmp_path)

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

    assert_equal 'test', cli.instance_variable_get(:@conf).environment.call
  ensure
    ENV.delete 'APP_ENV'
    ENV.delete 'RAILS_ENV'
  end

  def test_environment_rack_env
    ENV['RACK_ENV'] = @environment

    cli = Puma::CLI.new []
    cli.send(:setup_options)

    assert_equal @environment, cli.instance_variable_get(:@conf).environment.call
  end

  def test_environment_rails_env
    ENV.delete 'RACK_ENV'
    ENV['RAILS_ENV'] = @environment

    cli = Puma::CLI.new []
    cli.send(:setup_options)

    assert_equal @environment, cli.instance_variable_get(:@conf).environment.call
  ensure
    ENV.delete 'RAILS_ENV'
  end
end
