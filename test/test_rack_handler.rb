require_relative "helper"

# Most tests check that ::Rack::Handler::Puma works by itself
# RackUp#test_bin runs Puma using the rackup bin file
module TestRackUp
  require "rack/handler/puma"
  require "puma/events"

  begin
    require 'rackup/version'
  rescue LoadError
  end

  class TestOnBootedHandler < Minitest::Test
    def app
      Proc.new {|env| @input = env; [200, {}, ["hello world"]]}
    end

    # `Verbose: true` is included for `NameError`,
    # see https://github.com/puma/puma/pull/3118
    def test_after_booted
      after_booted = false
      events = Puma::Events.new
      events.after_booted do
        after_booted = true
      end

      launcher = nil
      thread = Thread.new do
        Rack::Handler::Puma.run(app, events: events, Verbose: true, Silent: true, Port: 0) do |l|
          launcher = l
        end
      end

      # Wait for launcher to boot
      Timeout.timeout(10) do
        sleep 0.5 until launcher
      end
      sleep 1.5 unless Puma::IS_MRI

      launcher.stop
      thread.join

      assert_equal after_booted, true
    end
  end

  class TestPathHandler < Minitest::Test
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

      # Wait for launcher to boot
      Timeout.timeout(10) do
        sleep 0.5 until @launcher
      end
      sleep 1.5 unless Puma::IS_MRI

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
        hit(["http://#{host}:#{port}/test"])
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

    def test_ssl_host_supplied_port_default
      @options[:Host] = "ssl://127.0.0.1"
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["ssl://127.0.0.1:9292"], conf.options[:binds]
    end

    def test_relative_unix_host
      @options[:Host] = "./relative.sock"
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["unix://./relative.sock"], conf.options[:binds]
    end

    def test_absolute_unix_host
      @options[:Host] = "/absolute.sock"
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["unix:///absolute.sock"], conf.options[:binds]
    end

    def test_abstract_unix_host
      @options[:Host] = "@abstract.sock"
      conf = ::Rack::Handler::Puma.config(->{}, @options)
      conf.load

      assert_equal ["unix://@abstract.sock"], conf.options[:binds]
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
  class RackUp < Minitest::Test
    def setup
      FileUtils.copy_file 'test/rackup/hello.ru', 'config.ru'
    end

    def teardown
      FileUtils.rm 'config.ru'
    end

    def test_bin
      pid = nil
      # JRuby & TruffleRuby take a long time using IO.popen
      skip_unless :mri
      io = IO.popen "rackup -p 0"
      io.wait_readable 2
      sleep 0.7
      log = io.sysread 2_048
      pid = log[/PID: (\d+)/, 1] || io.pid
      assert_includes log, 'Puma version'
      assert_includes log, 'Use Ctrl-C to stop'
    ensure
      if pid
        if Puma::IS_WINDOWS
          `taskkill /F /PID #{pid}`
        else
          `kill -s KILL #{pid}`
        end
      end
    end

    def test_rackup1
      pid = nil
      # JRuby & TruffleRuby take a long time using IO.popen
      skip_unless :mri
      env = {'RUBYOPT' => '-rbundler/setup -rrack/version -rrack/handler -rrackup -rrack/handler/puma'}
      io = IO.popen env, "ruby -e 'puts Rackup::VERSION'"
      io.wait_readable 2
      pid = io.pid
      log = io.sysread 2_048
      assert_start_with log, '1.0'
    ensure
      if pid
        if Puma::IS_WINDOWS
          `taskkill /F /PID #{pid}`
        else
          `kill -s KILL #{pid}`
        end
      end
    end if Object.const_defined?(:Rackup) && ::Rackup::VERSION.start_with?('1.')
  end
end
