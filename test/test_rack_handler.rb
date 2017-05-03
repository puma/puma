require_relative "helper"

require "rack/handler/puma"

class TestPumaUnixSocket < Minitest::Test
  def test_handler
    handler = Rack::Handler.get(:puma)
    assert_equal Rack::Handler::Puma, handler
    handler = Rack::Handler.get('Puma')
    assert_equal Rack::Handler::Puma, handler
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
      Rack::Handler::Puma.run(app, options) do |s, p|
        @launcher = s
      end
    end
    thread.abort_on_exception = true

    # Wait for launcher to boot
    Timeout.timeout(10) do
      until @launcher
        sleep 1
      end
    end
    sleep 1

    yield @launcher
  ensure
    @launcher.stop if @launcher
    thread.join  if thread
  end


  def test_handler_boots
    in_handler(app) do |launcher|
      hit(["http://0.0.0.0:#{ launcher.connected_port }/test"])
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
        conf = Rack::Handler::Puma.config(->{}, @options)
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
    conf = Rack::Handler::Puma.config(->{}, @options)
    conf.load

    assert_equal ["tcp://#{user_host}:#{user_port}"], conf.options[:binds]
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
        conf = Rack::Handler::Puma.config(->{}, @options)
        conf.load

        assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
      end
    end
  end
end

class TestUserSuppliedOptionsIsNotPresent < Minitest::Test
  def setup
    @options = {}
  end

  def test_default_port_when_no_config_file
    conf = Rack::Handler::Puma.config(->{}, @options)
    conf.load

    assert_equal ["tcp://0.0.0.0:9292"], conf.options[:binds]
  end

  def test_config_wins_over_default
    file_port = 6001

    Dir.mktmpdir do |d|
      Dir.chdir(d) do
        FileUtils.mkdir("config")
        File.open("config/puma.rb", "w") { |f| f << "port #{file_port}" }

        conf = Rack::Handler::Puma.config(-> {}, @options)
        conf.load

        assert_equal ["tcp://0.0.0.0:#{file_port}"], conf.options[:binds]
      end
    end
  end

  def test_user_port_wins_over_default
    user_port = 5001
    @options[:Port] = user_port
    conf = Rack::Handler::Puma.config(->{}, @options)
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
        conf = Rack::Handler::Puma.config(->{}, @options)
        conf.load

        assert_equal ["tcp://0.0.0.0:#{user_port}"], conf.options[:binds]
      end
    end
  end
end

