require_relative "helper"
require_relative "helpers/integration"

class TestURLMap < TestIntegration

  # make sure the mapping defined in url_map_test/config.ru works
  def test_basic_url_mapping
    skip_if :jruby
    env = { "BUNDLE_GEMFILE" => "#{__dir__}/url_map_test/Gemfile" }
    Dir.chdir("#{__dir__}/url_map_test") do
      cli_server set_pumactl_args, env: env
    end

    # Puma 6.2.2 and below will time out here with Ruby v3.3
    # see https://github.com/puma/puma/pull/3165
    body = send_http_read_resp_body "GET /ok HTTP/1.0\r\n\r\n"
    assert_equal("OK", body)
  end
end
