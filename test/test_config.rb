require 'test/unit'

require 'puma'
require 'puma/configuration'

class TestConfigFile < Test::Unit::TestCase
  def test_app_from_rackup
    conf = Puma::Configuration.new do |c|
      c.rackup "test/hello-bind.ru"
    end
    conf.load

    conf.app

    assert_equal ["tcp://127.0.0.1:9292"], conf.options[:binds]
  end

  def test_app_from_app_DSL
    conf = Puma::Configuration.new do |c|
      c.load "test/config/app.rb"
    end
    conf.load

    app = conf.app

    assert_equal [200, {}, ["embedded app"]], app.call({})
  end

  def test_double_bind_port
    port = (rand(10_000) + 30_000).to_s
    with_env("PORT" => port) do
      conf = Puma::Configuration.new do |c|
        c.bind "tcp://#{Puma::Configuration::DefaultTCPHost}:#{port}"
        c.load "test/config/app.rb"
      end

      conf.load

      assert_equal ["tcp://0.0.0.0:#{port}"], conf.options[:binds]
    end
  end

  def test_lowleve_error_handler_DSL
    conf = Puma::Configuration.new do |c|
      c.load "test/config/app.rb"
    end
    conf.load

    app = conf.options[:lowlevel_error_handler]

    assert_equal [200, {}, ["error page"]], app.call({})
  end

  def test_allow_users_to_override_default_options
    conf = Puma::Configuration.new(restart_cmd: 'bin/rails server')

    assert_equal 'bin/rails server', conf.options[:restart_cmd]
  end

  private

    def with_env(env = {})
      original_env = {}
      env.each do |k, v|
        original_env[k] = ENV[k]
        ENV[k] = v
      end
      yield
    ensure
      original_env.each do |k, v|
        ENV[k] = v
      end
    end
end
