# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"
require_relative "helpers/test_puma/puma_socket"

require "puma/configuration"
require 'puma/log_writer'

class TestWebConcurrencyAuto < TestIntegration

  include TestPuma::PumaSocket

  ENV_WC_TEST =  {
    # -W0 removes logging of bundled gem warnings
    "RUBYOPT" => "#{ENV["RUBYOPT"]} -W0",
    "WEB_CONCURRENCY" => "auto"
  }

  def teardown
    return if skipped?
    super
  end

  # we use `cli_server` so no concurrent_ruby files are loaded in the test process
  def test_web_concurrency_with_concurrent_ruby_available
    skip_unless :fork

    app = <<~APP
      cpus = Concurrent.available_processor_count.to_i
      silence_single_worker_warning if cpus == 1
      app { |_| [200, {}, [cpus.to_s]] }
    APP

    cli_server set_pumactl_args, env: ENV_WC_TEST, config: app

    # this is the value of `@options[:workers]` in Puma::Cluster
    actual = @server_log[/\* +Workers: +(\d+)$/, 1]

    workers = actual.to_i == 1 ? 1 : 2
    get_worker_pids 0, workers # make sure at least one or more workers booted

    expected = send_http_read_resp_body GET_11

    assert_equal expected, actual
  end

  def test_web_concurrency_with_concurrent_ruby_unavailable
    skip_unless :fork

    _, err = capture_io do
      assert_raises(LoadError) do
        conf = Puma::Configuration.new({}, {}, ENV_WC_TEST)
        # Mock the require to force it to fail
        def conf.require(*args)
          raise LoadError.new("Mocking system where concurrent-ruby is not available")
        end

        conf.puma_default_options(ENV_WC_TEST)
      end
    end
    assert_includes err, 'Please add "concurrent-ruby" to your Gemfile'
  end
end
