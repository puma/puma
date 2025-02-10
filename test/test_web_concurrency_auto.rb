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

    app = "app { |_| [200, {}, [Concurrent.available_processor_count.to_i.to_s]] }\n"

    cli_server set_pumactl_args, env: ENV_WC_TEST, config: app

    # this is the value of `@options[:workers]` in Puma::Cluster
    actual = @server_log[/\* +Workers: +(\d+)$/, 1]

    get_worker_pids 0, 2 # make sure some workers have booted

    expected = send_http_read_resp_body GET_11

    assert_equal expected, actual
  end

  # Rename the processor_counter file, then restore
  def test_web_concurrency_with_concurrent_ruby_unavailable
    file_path = nil
    skip_unless :fork

    ccr_gem = 'concurrent-ruby'
    file_require = 'concurrent/utility/processor_counter'
    file_path = Dir["#{ENV['GEM_HOME']}/gems/#{ccr_gem}-*/lib/#{ccr_gem}/#{file_require}.rb"].first

    if file_path && File.exist?(file_path)
      File.rename file_path, "#{file_path}_orig"
    else
      # cannot find concurrent-ruby file?
    end

    _, err = capture_io do
      assert_raises(LoadError) do
        conf = Puma::Configuration.new({}, {}, ENV_WC_TEST)
        conf.load
        conf.clamp
      end
    end
    assert_includes err, 'Please add "concurrent-ruby" to your Gemfile'

  ensure
    if file_path && File.exist?("#{file_path}_orig")
      File.rename "#{file_path}_orig", file_path
    end
  end
end
