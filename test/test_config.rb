require 'test/unit'

require 'puma'
require 'puma/configuration'

class TestConfigFile < Test::Unit::TestCase
  def test_app_from_app_DSL
    opts = { :config_file => "test/config/app.rb" }
    conf = Puma::Configuration.new opts
    conf.load

    app = conf.app

    assert_equal [200, {}, ["embedded app"]], app.call({})
  end

  def test_double_bind_port
    port = rand(30_000..40_000).to_s
    with_env("PORT" => port) do
      opts = { :binds => ["tcp://#{Configuration::DefaultTCPHost}:#{port}"], :config_file => "test/config/app.rb"}
      conf = Puma::Configuration.new opts
      conf.load

      assert_equal ["tcp://0.0.0.0:#{port}"], conf.options[:binds]
    end
  end

  def test_lowleve_error_handler_DSL
    opts = { :config_file => "test/config/app.rb" }
    conf = Puma::Configuration.new opts
    conf.load

    app = conf.options[:lowlevel_error_handler]

    assert_equal [200, {}, ["error page"]], app.call({})
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
