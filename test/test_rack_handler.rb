require_relative "helper"

require "rack"

module TestRackUp
  if Rack::RELEASE < '3'
    require "rack/handler/puma"
    RACK_HANDLER_MOD = ::Rack::Handler
  else
    require "rackup"
    require "rack/handler/puma"
    RACK_HANDLER_MOD = ::Rackup::Handler
  end

  class TestHandlerGetStrSym < Minitest::Test
    def test_handler
      handler = RACK_HANDLER_MOD.get(:puma)
      assert_equal RACK_HANDLER_MOD::Puma, handler
      handler = RACK_HANDLER_MOD.get('Puma')
      assert_equal RACK_HANDLER_MOD::Puma, handler
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
        RACK_HANDLER_MOD::Puma.run(app, **options) do |s, p|
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
          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://#{user_host}:#{user_port}"], conf.options[:binds]
    end

    def test_ipv6_host_supplied_port_default
      @options[:Host] = "::1"
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://0.0.0.0:9292"], conf.options[:binds]
    end

    def test_config_wins_over_default
      file_port = 6001

      Dir.mktmpdir do |d|
        Dir.chdir(d) do
          FileUtils.mkdir("config")
          File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
        end
      end
    end

    def test_user_port_wins_over_default_when_user_supplied_is_blank
      user_port = 5001
      @options[:user_supplied_options] = []
      @options[:Port] = user_port
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
    end

    def test_user_port_wins_over_default
      user_port = 5001
      @options[:Port] = user_port
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
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
          conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
          conf.load

          assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
        end
      end
    end

    def test_default_log_request_when_no_config_file
      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal false, conf.options[:log_requests]
    end

    def test_file_log_requests_wins_over_default_config
      file_log_requests_config = true

      @options[:config_files] = [
        'test/config/t1_conf.rb'
      ]

      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal file_log_requests_config, conf.options[:log_requests]
    end

    def test_user_log_requests_wins_over_file_config
      user_log_requests_config = false

      @options[:log_requests] = user_log_requests_config
      @options[:config_files] = [
        'test/config/t1_conf.rb'
      ]

      conf = RACK_HANDLER_MOD::Puma.config(->{}, @options)
      conf.load

      assert_equal user_log_requests_config, conf.options[:log_requests]
    end
  end
end
