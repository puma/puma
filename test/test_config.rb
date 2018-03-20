require_relative "helper"

require "puma/configuration"

class TestConfigFile < Minitest::Test
  def setup
    FileUtils.mkpath("config/puma")
    File.write("config/puma/fake-env.rb", "")
  end

  def test_app_from_rackup
    conf = Puma::Configuration.new do |c|
      c.rackup "test/rackup/hello-bind.ru"
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
      conf = Puma::Configuration.new do |user_config, file_config, default_config|
        user_config.bind "tcp://#{Puma::Configuration::DefaultTCPHost}:#{port}"
        file_config.load "test/config/app.rb"
      end

      conf.load
      assert_equal ["tcp://0.0.0.0:#{port}"], conf.options[:binds]
    end
  end

  def test_lowlevel_error_handler_DSL
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

  def test_overwrite_options
    conf = Puma::Configuration.new do |c|
      c.workers 3
    end
    conf.load

    assert_equal conf.options[:workers], 3
    conf.options[:workers] += 1
    assert_equal conf.options[:workers], 4
  end

  def test_explicit_config_files
    conf = Puma::Configuration.new(config_files: ['test/config/settings.rb']) do |c|
    end
    conf.load
    assert_match(/:3000$/, conf.options[:binds].first)
  end

  def test_parameters_overwrite_files
    conf = Puma::Configuration.new(config_files: ['test/config/settings.rb']) do |c|
      c.port 3030
    end
    conf.load

    assert_match(/:3030$/, conf.options[:binds].first)
    assert_equal 3, conf.options[:min_threads]
    assert_equal 5, conf.options[:max_threads]
  end

  def test_config_files_default
    conf = Puma::Configuration.new do
    end

    assert_equal [nil], conf.config_files
  end

  def test_config_files_with_dash
    conf = Puma::Configuration.new(config_files: ['-']) do
    end

    assert_equal [], conf.config_files
  end

  def test_config_files_with_existing_path
    conf = Puma::Configuration.new(config_files: ['test/config/settings.rb']) do
    end

    assert_equal ['test/config/settings.rb'], conf.config_files
  end

  def test_config_files_with_non_existing_path
    conf = Puma::Configuration.new(config_files: ['test/config/typo/settings.rb']) do
    end

    assert_equal ['test/config/typo/settings.rb'], conf.config_files
  end

  def test_config_files_with_rack_env
    with_env('RACK_ENV' => 'fake-env') do
      conf = Puma::Configuration.new do
      end

      assert_equal ['config/puma/fake-env.rb'], conf.config_files
    end
  end

  def test_config_files_with_specified_environment
    conf = Puma::Configuration.new do
    end

    conf.options[:environment] = 'fake-env'

    assert_equal ['config/puma/fake-env.rb'], conf.config_files
  end

  def test_config_files_with_integer_convert
    conf = Puma::Configuration.new(config_files: ['test/config/with_integer_convert.rb']) do
    end
    conf.load

    assert_equal 6, conf.options[:persistent_timeout]
    assert_equal 3, conf.options[:first_data_timeout]
    assert_equal 2, conf.options[:workers]
    assert_equal 4, conf.options[:min_threads]
    assert_equal 8, conf.options[:max_threads]
    assert_equal 90, conf.options[:worker_timeout]
    assert_equal 120, conf.options[:worker_boot_timeout]
    assert_equal 150, conf.options[:worker_shutdown_timeout]
  end

  def teardown
    FileUtils.rm_r("config/puma")
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
