# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/config_file"

require "puma/configuration"
require 'puma/events'

class TestConfigFile < TestConfigFileBase
  parallelize_me!

  def test_default_max_threads
    max_threads = 16
    max_threads = 5 if RUBY_ENGINE.nil? || RUBY_ENGINE == 'ruby'
    assert_equal max_threads, Puma::Configuration.new.default_max_threads
  end


  def test_app_from_rackup
    conf = Puma::Configuration.new do |c|
      c.rackup "test/rackup/hello-bind.ru"
    end
    conf.load

    # suppress deprecation warning of Rack (>= 2.2.0)
    # > Parsing options from the first comment line is deprecated!\n
    assert_output(nil, nil) do
      conf.app
    end

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

  def test_ssl_configuration_from_DSL
    skip 'No ssl support' unless ::Puma::HAS_SSL
    conf = Puma::Configuration.new do |config|
      config.load "test/config/ssl_config.rb"
    end

    conf.load

    bind_configuration = conf.options.file_options[:binds].first
    app = conf.app

    assert bind_configuration =~ %r{ca=.*ca.crt}
    assert bind_configuration =~ /verify_mode=peer/

    assert_equal [200, {}, ["embedded app"]], app.call({})
  end

  def test_ssl_bind
    skip_on :jruby
    skip 'No ssl support' unless ::Puma::HAS_SSL

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert",
        key: "/path/to/key",
        verify_mode: "the_verify_mode",
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=/path/to/cert&key=/path/to/key&verify_mode=the_verify_mode"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_jruby
    skip_unless :jruby
    skip 'No ssl support' unless ::Puma::HAS_SSL

    cipher_list = "TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        keystore: "/path/to/keystore",
        keystore_pass: "password",
        ssl_cipher_list: cipher_list,
        verify_mode: "the_verify_mode"
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?keystore=/path/to/keystore" \
      "&keystore-pass=password&ssl_cipher_list=#{cipher_list}" \
      "&verify_mode=the_verify_mode"
    assert_equal [ssl_binding], conf.options[:binds]
  end




  def test_ssl_bind_no_tlsv1_1
    skip_on :jruby
    skip 'No ssl support' unless ::Puma::HAS_SSL

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert",
        key: "/path/to/key",
        verify_mode: "the_verify_mode",
        no_tlsv1_1: true
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=/path/to/cert&key=/path/to/key&verify_mode=the_verify_mode&no_tlsv1_1=true"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_with_cipher_filter
    skip_on :jruby
    skip 'No ssl support' unless ::Puma::HAS_SSL

    cipher_filter = "!aNULL:AES+SHA"
    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "cert",
        key: "key",
        ssl_cipher_filter: cipher_filter,
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?("&ssl_cipher_filter=#{cipher_filter}")
  end

  def test_ssl_bind_with_verification_flags
    skip_on :jruby
    skip 'No ssl support' unless ::Puma::HAS_SSL

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "cert",
        key: "key",
        verification_flags: ["TRUSTED_FIRST", "NO_CHECK_TIME"]
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?("&verification_flags=TRUSTED_FIRST,NO_CHECK_TIME")
  end

  def test_ssl_bind_with_ca
    skip 'No ssl support' unless ::Puma::HAS_SSL
    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert",
        ca: "/path/to/ca",
        key: "/path/to/key",
        verify_mode: :peer,
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert_match "ca=/path/to/ca", ssl_binding
    assert_match "verify_mode=peer", ssl_binding
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

  def test_config_files_with_float_convert
    conf = Puma::Configuration.new(config_files: ['test/config/with_float_convert.rb']) do
    end
    conf.load

    assert_equal Float::INFINITY, conf.options[:max_fast_inline]
  end

  def test_config_files_with_symbol_convert
    conf = Puma::Configuration.new(config_files: ['test/config/with_symbol_convert.rb']) do
    end
    conf.load

    assert_equal :ruby, conf.options[:io_selector_backend]
  end

  def test_config_raise_exception_on_sigterm
    conf = Puma::Configuration.new do |c|
      c.raise_exception_on_sigterm false
    end
    conf.load

    assert_equal conf.options[:raise_exception_on_sigterm], false
    conf.options[:raise_exception_on_sigterm] = true
    assert_equal conf.options[:raise_exception_on_sigterm], true
  end

  def test_run_hooks_on_restart_hook
    assert_run_hooks :on_restart
  end

  def test_run_hooks_before_worker_fork
    assert_run_hooks :before_worker_fork, configured_with: :on_worker_fork
  end

  def test_run_hooks_after_worker_fork
    assert_run_hooks :after_worker_fork
  end

  def test_run_hooks_before_worker_boot
    assert_run_hooks :before_worker_boot, configured_with: :on_worker_boot
  end

  def test_run_hooks_before_worker_shutdown
    assert_run_hooks :before_worker_shutdown, configured_with: :on_worker_shutdown
  end

  def test_run_hooks_before_fork
    assert_run_hooks :before_fork
  end

  def test_run_hooks_and_exception
    conf = Puma::Configuration.new do |c|
      c.on_restart do |a|
        raise RuntimeError, 'Error from hook'
      end
    end
    conf.load
    events = Puma::Events.strings

    conf.run_hooks :on_restart, 'ARG', events
    expected = /WARNING hook on_restart failed with exception \(RuntimeError\) Error from hook/
    assert_match expected, events.stdout.string
  end

  def test_config_does_not_load_workers_by_default
    assert_equal 0, Puma::Configuration.new.options.default_options[:workers]
  end

  def test_final_options_returns_merged_options
    conf = Puma::Configuration.new({ min_threads: 1, max_threads: 2 }, { min_threads: 2 })

    assert_equal 1, conf.final_options[:min_threads]
    assert_equal 2, conf.final_options[:max_threads]
  end

  def test_silence_single_worker_warning_default
    conf = Puma::Configuration.new
    conf.load

    assert_equal false, conf.options[:silence_single_worker_warning]
  end

  def test_silence_single_worker_warning_overwrite
    conf = Puma::Configuration.new do |c|
      c.silence_single_worker_warning
    end
    conf.load

    assert_equal true, conf.options[:silence_single_worker_warning]
  end

  private

  def assert_run_hooks(hook_name, options = {})
    configured_with = options[:configured_with] || hook_name

    messages = []
    conf = Puma::Configuration.new do |c|
      c.send(configured_with) do |a|
        messages << "#{hook_name} is called with #{a}"
      end
    end
    conf.load

    conf.run_hooks hook_name, 'ARG', Puma::Events.strings
    assert_equal messages, ["#{hook_name} is called with ARG"]
  end
end

# Thread unsafe modification of ENV
class TestEnvModifificationConfig < TestConfigFileBase
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
end

class TestConfigEnvVariables < TestConfigFileBase
  def test_config_loads_correct_min_threads
    assert_equal 0, Puma::Configuration.new.options.default_options[:min_threads]

    with_env("MIN_THREADS" => "7") do
      conf = Puma::Configuration.new
      assert_equal 7, conf.options.default_options[:min_threads]
    end

    with_env("PUMA_MIN_THREADS" => "8") do
      conf = Puma::Configuration.new
      assert_equal 8, conf.options.default_options[:min_threads]
    end
  end

  def test_config_loads_correct_max_threads
    conf = Puma::Configuration.new
    assert_equal conf.default_max_threads, conf.options.default_options[:max_threads]

    with_env("MAX_THREADS" => "7") do
      conf = Puma::Configuration.new
      assert_equal 7, conf.options.default_options[:max_threads]
    end

    with_env("PUMA_MAX_THREADS" => "8") do
      conf = Puma::Configuration.new
      assert_equal 8, conf.options.default_options[:max_threads]
    end
  end

  def test_config_loads_workers_from_env
    with_env("WEB_CONCURRENCY" => "9") do
      conf = Puma::Configuration.new
      assert_equal 9, conf.options.default_options[:workers]
    end
  end

  def test_config_does_not_preload_app_if_not_using_workers
    with_env("WEB_CONCURRENCY" => "0") do
      conf = Puma::Configuration.new
      assert_equal false, conf.options.default_options[:preload_app]
    end
  end

  def test_config_preloads_app_if_using_workers
    with_env("WEB_CONCURRENCY" => "2") do
      preload = Puma.forkable?
      conf = Puma::Configuration.new
      assert_equal preload, conf.options.default_options[:preload_app]
    end
  end
end

class TestConfigFileWithFakeEnv < TestConfigFileBase
  def setup
    FileUtils.mkpath("config/puma")
    File.write("config/puma/fake-env.rb", "")
  end

  def test_config_files_with_rack_env
    with_env('RACK_ENV' => 'fake-env') do
      conf = Puma::Configuration.new do
      end

      assert_equal ['config/puma/fake-env.rb'], conf.config_files
    end
  end

  def test_config_files_with_rails_env
    with_env('RAILS_ENV' => 'fake-env', 'RACK_ENV' => nil) do
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

  def teardown
    FileUtils.rm_r("config/puma")
  end
end
