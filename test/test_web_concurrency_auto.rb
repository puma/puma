require_relative "helper"
require_relative "helpers/integration"

class TestWebConcurrencyAuto < TestIntegration

  def teardown
    return if skipped?
    super
  end

  def test_web_concurrency_with_concurrent_ruby_available
    skip_unless :fork
    env = {
      "BUNDLE_GEMFILE" => "#{__dir__}/web_concurrency_test/Gemfile",
      "WEB_CONCURRENCY" => "auto"
    }
    Dir.chdir("#{__dir__}/web_concurrency_test") do
      with_unbundled_env do
        silent_and_checked_system_command("bundle config --local path vendor/bundle")
        silent_and_checked_system_command("bundle install")
      end
      cli_server set_pumactl_args, env: env
    end

    connection = connect("/worker_count")
    body = read_body(connection, 1)
    assert_equal(get_stats.fetch("workers").to_s, body)
  end
end
