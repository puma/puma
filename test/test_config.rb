# frozen_string_literal: true

require_relative "helper"

require "puma/configuration"
require 'puma/log_writer'
require 'rack'

class TestConfigFile < Minitest::Test
  parallelize_me!

  def test_default_max_threads
    max_threads = 16
    max_threads = 5 if RUBY_ENGINE.nil? || RUBY_ENGINE == 'ruby'
    assert_equal max_threads, Puma::Configuration.new.options.default_options[:max_threads]
  end

  def test_app_from_rackup
    if Rack.release >= '3'
      fn = "test/rackup/hello-bind_rack3.ru"
      bind = "tcp://0.0.0.0:9292"
    else
      fn = "test/rackup/hello-bind.ru"
      bind = "tcp://127.0.0.1:9292"
    end

    conf = Puma::Configuration.new do |c|
      c.rackup fn
    end
    conf.load

    # suppress deprecation warning of Rack (>= 2.2.0)
    # > Parsing options from the first comment line is deprecated!\n
    assert_output(nil, nil) do
      conf.app
    end

    assert_equal [200, {"Content-Type"=>"text/plain"}, ["Hello World"]], conf.app.call({})

    assert_equal [bind], conf.options[:binds]
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
    skip_unless :ssl
    conf = Puma::Configuration.new do |config|
      config.load "test/config/ssl_config.rb"
    end

    conf.load

    bind_configuration = conf.options.file_options[:binds].first
    app = conf.app

    assert bind_configuration =~ %r{ca=.*ca.crt}
    assert bind_configuration&.include?('verify_mode=peer')

    assert_equal [200, {}, ["embedded app"]], app.call({})
  end

  def test_ssl_self_signed_configuration_from_DSL
    skip_if :jruby
    skip_unless :ssl
    conf = Puma::Configuration.new do |config|
      config.load "test/config/ssl_self_signed_config.rb"
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?&verify_mode=none"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind
    skip_if :jruby
    skip_unless :ssl

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert",
        key: "/path/to/key",
        verify_mode: "the_verify_mode",
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=%2Fpath%2Fto%2Fcert&key=%2Fpath%2Fto%2Fkey&verify_mode=the_verify_mode"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_with_escaped_filenames
    skip_if :jruby
    skip_unless :ssl

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert+1",
        ca: "/path/to/ca+1",
        key: "/path/to/key+1",
        verify_mode: :peer
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=%2Fpath%2Fto%2Fcert%2B1&key=%2Fpath%2Fto%2Fkey%2B1&verify_mode=peer&ca=%2Fpath%2Fto%2Fca%2B1"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_with_cert_and_key_pem
    skip_if :jruby
    skip_unless :ssl

    cert_path = File.expand_path "../examples/puma/client_certs", __dir__
    cert_pem = File.read("#{cert_path}/server.crt")
    key_pem = File.read("#{cert_path}/server.key")

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert_pem: cert_pem,
        key_pem: key_pem,
        verify_mode: "the_verify_mode",
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=store%3A0&key=store%3A1&verify_mode=the_verify_mode"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_with_backlog
    skip_unless :ssl

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        backlog: "2048",
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?('&backlog=2048')
  end

  def test_ssl_bind_with_low_latency_true
    skip_unless :ssl
    skip_if :jruby

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        low_latency: true
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?('&low_latency=true')
  end

  def test_ssl_bind_with_low_latency_false
    skip_unless :ssl
    skip_if :jruby

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        low_latency: false
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?('&low_latency=false')
  end

  def test_ssl_bind_jruby
    skip_unless :jruby
    skip_unless :ssl

    ciphers = "TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
          keystore: "/path/to/keystore",
          keystore_pass: "password",
          cipher_suites: ciphers,
          protocols: 'TLSv1.2',
          verify_mode: "the_verify_mode"
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?keystore=/path/to/keystore" \
      "&keystore-pass=password&cipher_suites=#{ciphers}&protocols=TLSv1.2" \
      "&verify_mode=the_verify_mode"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_jruby_with_ssl_cipher_list
    skip_unless :jruby
    skip_unless :ssl

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

  def test_ssl_bind_jruby_with_truststore
    skip_unless :jruby
    skip_unless :ssl

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
          keystore: "/path/to/keystore",
          keystore_type: "pkcs12",
          keystore_pass: "password",
          truststore: "default",
          truststore_type: "jks",
          verify_mode: "none"
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?keystore=/path/to/keystore" \
      "&keystore-pass=password&keystore-type=pkcs12" \
      "&truststore=default&truststore-type=jks" \
      "&verify_mode=none"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_no_tlsv1_1
    skip_if :jruby
    skip_unless :ssl

    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "/path/to/cert",
        key: "/path/to/key",
        verify_mode: "the_verify_mode",
        no_tlsv1_1: true
      }
    end

    conf.load

    ssl_binding = "ssl://0.0.0.0:9292?cert=%2Fpath%2Fto%2Fcert&key=%2Fpath%2Fto%2Fkey&verify_mode=the_verify_mode&no_tlsv1_1=true"
    assert_equal [ssl_binding], conf.options[:binds]
  end

  def test_ssl_bind_with_cipher_filter
    skip_if :jruby
    skip_unless :ssl

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

  def test_ssl_bind_with_ciphersuites
    skip_if :jruby
    skip_unless :ssl
    skip('Requires TLSv1.3') unless Puma::MiniSSL::HAS_TLS1_3

    ciphersuites = "TLS_AES_256_GCM_SHA384:TLS_AES_128_GCM_SHA256"
    conf = Puma::Configuration.new do |c|
      c.ssl_bind "0.0.0.0", "9292", {
        cert: "cert",
        key: "key",
        ssl_ciphersuites: ciphersuites,
      }
    end

    conf.load

    ssl_binding = conf.options[:binds].first
    assert ssl_binding.include?("&ssl_ciphersuites=#{ciphersuites}")
  end

  def test_ssl_bind_with_verification_flags
    skip_if :jruby
    skip_unless :ssl

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
    skip_unless :ssl
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
    assert_includes ssl_binding, Puma::Util.escape("/path/to/ca")
    assert_includes ssl_binding, "verify_mode=peer"
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

  def test_run_hooks_before_restart_hook
    assert_run_hooks :before_restart
    assert_run_hooks :before_restart, configured_with: :on_restart
  end

  def test_run_hooks_before_worker_fork
    assert_run_hooks :before_worker_fork
    assert_run_hooks :before_worker_fork, configured_with: :on_worker_fork

    assert_warning_for_hooks_defined_in_single_mode :before_worker_fork
  end

  def test_run_hooks_after_worker_fork
    assert_run_hooks :after_worker_fork

    assert_warning_for_hooks_defined_in_single_mode :after_worker_fork
  end

  def test_run_hooks_before_worker_boot
    assert_run_hooks :before_worker_boot
    assert_run_hooks :before_worker_boot, configured_with: :on_worker_boot

    assert_warning_for_hooks_defined_in_single_mode :before_worker_boot
  end

  def test_run_hooks_before_worker_shutdown
    assert_run_hooks :before_worker_shutdown
    assert_run_hooks :before_worker_shutdown, configured_with: :on_worker_shutdown

    assert_warning_for_hooks_defined_in_single_mode :before_worker_shutdown
  end

  def test_run_hooks_before_fork
    assert_run_hooks :before_fork

    assert_warning_for_hooks_defined_in_single_mode :before_fork
  end

  def test_run_hooks_before_refork
    assert_run_hooks :before_refork
    assert_run_hooks :before_refork, configured_with: :on_refork

    assert_warning_for_hooks_defined_in_single_mode :before_refork
  end

  def test_run_hooks_before_thread_start
    assert_run_hooks :before_thread_start
    assert_run_hooks :before_thread_start, configured_with: :on_thread_start
  end

  def test_run_hooks_before_thread_exit
    assert_run_hooks :before_thread_exit
    assert_run_hooks :before_thread_exit, configured_with: :on_thread_exit
  end

  def test_run_hooks_out_of_band
    assert_run_hooks :out_of_band
  end

  def test_run_hooks_and_exception
    conf = Puma::Configuration.new do |c|
      c.before_restart do |a|
        raise RuntimeError, 'Error from hook'
      end
    end
    conf.load
    log_writer = Puma::LogWriter.strings

    conf.run_hooks(:before_restart, 'ARG', log_writer)
    expected = /WARNING hook before_restart failed with exception \(RuntimeError\) Error from hook/
    assert_match expected, log_writer.stdout.string
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

  def test_silence_fork_callback_warning_default
    conf = Puma::Configuration.new
    conf.load

    assert_equal false, conf.options[:silence_fork_callback_warning]
  end

  def test_silence_fork_callback_warning_overwrite
    conf = Puma::Configuration.new do |c|
      c.silence_fork_callback_warning
    end
    conf.load

    assert_equal true, conf.options[:silence_fork_callback_warning]
  end

  def test_http_content_length_limit
    assert_nil Puma::Configuration.new.options.default_options[:http_content_length_limit]

    conf = Puma::Configuration.new({ http_content_length_limit: 10000})

    assert_equal 10000, conf.final_options[:http_content_length_limit]
  end

  private

  def assert_run_hooks(hook_name, options = {})
    configured_with = options[:configured_with] || hook_name

    # test single, not an array
    messages = []
    conf = Puma::Configuration.new do |c|
      c.silence_fork_callback_warning
    end
    conf.options[hook_name] = -> (a) {
      messages << "#{hook_name} is called with #{a}"
    }

    conf.run_hooks(hook_name, 'ARG', Puma::LogWriter.strings)
    assert_equal messages, ["#{hook_name} is called with ARG"]

    # test multiple
    messages = []
    conf = Puma::Configuration.new do |c|
      c.silence_fork_callback_warning

      c.send(configured_with) do |a|
        messages << "#{hook_name} is called with #{a} one time"
      end

      c.send(configured_with) do |a|
        messages << "#{hook_name} is called with #{a} a second time"
      end
    end
    conf.load

    conf.run_hooks(hook_name, 'ARG', Puma::LogWriter.strings)
    assert_equal messages, ["#{hook_name} is called with ARG one time", "#{hook_name} is called with ARG a second time"]
  end

  def assert_warning_for_hooks_defined_in_single_mode(hook_name)
    out, _ = capture_io do
      Puma::Configuration.new do |c|
        c.send(hook_name)
      end
    end

    assert_match "your `#{hook_name}` block will not run.\n", out
  end
end

# contains tests that cannot run parallel
class TestConfigFileSingle < Minitest::Test
  def test_custom_logger_from_DSL
    conf = Puma::Configuration.new { |c| c.load 'test/config/custom_logger.rb' }

    conf.load
    out, _ = capture_subprocess_io { conf.options[:custom_logger].write 'test' }

    assert_equal "Custom logging: test\n", out
  end
end

# Thread unsafe modification of ENV
class TestEnvModifificationConfig < Minitest::Test
  def test_double_bind_port
    port = (rand(10_000) + 30_000).to_s
    env = { "PORT" => port }
    conf = Puma::Configuration.new({}, {}, env)  do |user_config, file_config, default_config|
      user_config.bind "tcp://#{Puma::Configuration::DEFAULTS[:tcp_host]}:#{port}"
      file_config.load "test/config/app.rb"
    end

    conf.load
    assert_equal ["tcp://0.0.0.0:#{port}"], conf.options[:binds]
  end
end

class TestConfigEnvVariables < Minitest::Test
  def test_config_loads_correct_min_threads
    assert_equal 0, Puma::Configuration.new.options.default_options[:min_threads]

    env = { "MIN_THREADS" => "7" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 7, conf.options.default_options[:min_threads]

    env = { "PUMA_MIN_THREADS" => "8" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 8, conf.options.default_options[:min_threads]

    env = { "PUMA_MIN_THREADS" => "" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 0, conf.options.default_options[:min_threads]
  end

  def test_config_loads_correct_max_threads
    default_max_threads = Puma.mri? ? 5 : 16
    assert_equal default_max_threads, Puma::Configuration.new.options.default_options[:max_threads]

    env = { "MAX_THREADS" => "7" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 7, conf.options.default_options[:max_threads]

    env = { "PUMA_MAX_THREADS" => "8" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 8, conf.options.default_options[:max_threads]

    env = { "PUMA_MAX_THREADS" => "" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal default_max_threads, conf.options.default_options[:max_threads]
  end

  def test_config_loads_workers_from_env
    env = { "WEB_CONCURRENCY" => "9" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 9, conf.options.default_options[:workers]
  end

  def test_config_ignores_blank_workers_from_env
    env = { "WEB_CONCURRENCY" => "" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal 0, conf.options.default_options[:workers]
  end

  def test_config_does_not_preload_app_if_not_using_workers
    env = { "WEB_CONCURRENCY" => "0" }
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal false, conf.options.default_options[:preload_app]
  end

  def test_config_preloads_app_if_using_workers
    env = { "WEB_CONCURRENCY" => "2" }
    preload = Puma.forkable?
    conf = Puma::Configuration.new({}, {}, env)
    assert_equal preload, conf.options.default_options[:preload_app]
  end
end

class TestConfigFileWithFakeEnv < Minitest::Test
  def setup
    FileUtils.mkpath("config/puma")
    File.write("config/puma/fake-env.rb", "")
  end

  def teardown
    FileUtils.rm_r("config/puma")
  end

  def test_config_files_with_app_env
    env = { 'APP_ENV' => 'fake-env' }

    conf = Puma::Configuration.new({}, {}, env)

    assert_equal ['config/puma/fake-env.rb'], conf.config_files
  end

  def test_config_files_with_rack_env
    env = { 'RACK_ENV' => 'fake-env' }

    conf = Puma::Configuration.new({}, {}, env)

    assert_equal ['config/puma/fake-env.rb'], conf.config_files
  end

  def test_config_files_with_rails_env
    env = { 'RAILS_ENV' => 'fake-env', 'RACK_ENV' => nil }

    conf = Puma::Configuration.new({}, {}, env)

    assert_equal ['config/puma/fake-env.rb'], conf.config_files
  end

  def test_config_files_with_specified_environment
    conf = Puma::Configuration.new

    conf.options[:environment] = 'fake-env'

    assert_equal ['config/puma/fake-env.rb'], conf.config_files
  end

  def test_enable_keep_alives_by_default
    conf = Puma::Configuration.new
    conf.load

    assert_equal conf.options[:enable_keep_alives], true
  end

  def test_enable_keep_alives_true
    conf = Puma::Configuration.new do |c|
      c.enable_keep_alives true
    end
    conf.load

    assert_equal conf.options[:enable_keep_alives], true
  end

  def test_enable_keep_alives_false
    conf = Puma::Configuration.new do |c|
      c.enable_keep_alives false
    end
    conf.load

    assert_equal conf.options[:enable_keep_alives], false
  end
end
