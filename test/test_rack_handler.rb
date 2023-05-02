require_relative "helper"
require_relative "helpers/integration"
require_relative "helpers/puma_socket"

# Most tests check that ::Rack::Handler::Puma works by itself
# RackUp#test_bin runs Puma using the rackup bin file
module TestRackUp
  require "rack/handler/puma"
  require "puma/events"

  class TestOnBootedHandler < Minitest::Test
    def app
      Proc.new {|env| @input = env; [200, {}, ["hello world"]]}
    end

    # `Verbose: true` is included for `NameError`,
    # see https://github.com/puma/puma/pull/3118
    def test_on_booted
      on_booted = false
      events = Puma::Events.new
      events.on_booted do
        on_booted = true
      end

      launcher = nil
      thread = Thread.new do
        Rack::Handler::Puma.run(app, events: events, Verbose: true, Silent: true) do |l|
          launcher = l
        end
      end

      # Wait for launcher to boot
      Timeout.timeout(10) do
        sleep 0.5 until launcher && launcher.log_writer.stdout.string.include?('Use Ctrl-C to stop')
      end

      launcher.stop
      thread.join

      assert_equal on_booted, true
    end
  end

  class TestPathHandler < Minitest::Test
    include PumaTest::PumaSocket

    def app
      Proc.new {|env| @input = env; [200, {}, ["hello world"]]}
    end

    def setup
      @input = nil
    end

    def in_handler(app, options = {})
      options[:Port] ||= 0
      options[:Silent] = true

      @launcher = nil
      thread = Thread.new do
        ::Rack::Handler::Puma.run(app, **options) do |s, p|
          @launcher = s
        end
      end

      time_limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10.0
      booted = false

      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < time_limit
        if @launcher && @launcher.log_writer.stdout.string.include?('Use Ctrl-C to stop')
          booted = true
          break
        else
          sleep 0.1
        end
      end
      assert booted, 'Puma did not boot in 10 seconds?'

      yield @launcher
    ensure
      @launcher&.stop
      thread&.join
    end

    def test_handler_boots
      host = '127.0.0.1'
      port = UniquePort.call
      opts = { Host: host, Port: port }
      in_handler(app, opts) do |launcher|
        send_http_read_response "GET /test HTTP/1.1\r\n\r\n", port: port
        assert_equal("/test", @input["PATH_INFO"])
      end
    end
  end

  class TestUserSuppliedOptionsPortIsSet < Minitest::Test
    def setup
      @options = {}
      @options[:user_supplied_options] = [:Port]
    end

    def test_port_wins_over_config
      user_port = 5001
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          @options[:Port] = user_port
          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
        end
      end
    end
  end

  class TestUserSuppliedOptionsHostIsSet < Minitest::Test
    def setup
      @options = {}
      @options[:user_supplied_options] = [:Host]
    end

    def test_host_uses_supplied_port_default
      user_port = rand(1000..9999)
      user_host = "123.456.789"

      @options[:Host] = user_host
      @options[:Port] = user_port
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://#{user_host}:#{user_port}"], conf.options[:binds]
    end

    def test_ipv6_host_supplied_port_default
      @options[:Host] = "::1"
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://[::1]:9292"], conf.options[:binds]
    end
  end

  class TestUserSuppliedOptionsIsEmpty < Minitest::Test
    def setup
      @options = {}
      @options[:user_supplied_options] = []
    end

    def test_config_file_wins_over_port
      user_port = 5001
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          @options[:Port] = user_port
          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
        end
      end
    end

    def test_default_host_when_using_config_file
      user_port = 5001
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          @options[:Host] = "localhost"
          @options[:Port] = user_port
          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://localhost:#{file_port}"], conf.options[:binds]
        end
      end
    end

    def test_default_host_when_using_config_file_with_explicit_host
      user_port = 5001
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}, '1.2.3.4'" }

          @options[:Host] = "localhost"
          @options[:Port] = user_port
          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://1.2.3.4:#{file_port}"], conf.options[:binds]
        end
      end
    end
  end

  class TestUserSuppliedOptionsIsNotPresent < Minitest::Test
    def setup
      @options = {}
    end

    def test_default_port_when_no_config_file
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://0.0.0.0:9292"], conf.options[:binds]
    end

    def test_config_wins_over_default
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
        end
      end
    end

    def test_user_port_wins_over_default_when_user_supplied_is_blank
      user_port = 5001
      @options[:user_supplied_options] = []
      @options[:Port] = user_port
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
    end

    def test_user_port_wins_over_default
      user_port = 5001
      @options[:Port] = user_port
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
    end

    def test_user_port_wins_over_config
      user_port = 5001
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          @options[:Port] = user_port
          conf = ::Rack::Handler::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
        end
      end
    end

    def test_default_log_request_when_no_config_file
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal false, conf.options[:log_requests]
    end

    def test_file_log_requests_wins_over_default_config
      file_log_requests_config = true

      @options[:config_files] = [
        'test/config/t1_conf.rb'
      ]

      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal file_log_requests_config, conf.options[:log_requests]
    end

    def test_user_log_requests_wins_over_file_config
      user_log_requests_config = false

      @options[:log_requests] = user_log_requests_config
      @options[:config_files] = [
        'test/config/t1_conf.rb'
      ]

      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal user_log_requests_config, conf.options[:log_requests]
    end
  end

  # Run using IO.popen so we don't load Rack and/or Rackup in the main process
#  class RackUp < Minitest::Test
  class RackUp < TestIntegration
    def setup
    end

    def teardown
      return if skipped?
      Dir.chdir "tmp/rackup" do
        FileUtils.rm 'config.ru'
      end

      if Puma::IS_WINDOWS
        `taskkill /F /PID #{@pid}`
      else
        Process.kill :KILL, @pid
        begin
          Process.wait2 @pid
        rescue Errno::ECHILD
        end
      end
      @out.close unless @out.closed?
      @err.close unless @err.closed?
    end

    def test_bin
      skip_unless :mri

      Dir.mkdir 'tmp/rackup' unless Dir.exist? 'tmp/rackup'
      FileUtils.copy_file 'test/rackup/hello.ru', 'tmp/rackup/config.ru'

      Dir.chdir('tmp/rackup') { @out, @err, @pid = spawn_cmd "bundle exec rackup -p 0" }

      assert wait_for_server_to_include 'Puma version', io: @out
      assert wait_for_server_to_include 'Use Ctrl-C to stop', io: @out
    end
  end
end
