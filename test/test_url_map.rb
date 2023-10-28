# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestURLMap < TestPuma::ServerSpawn

  # make sure the mapping defined in url_map_test/config.ru works
  def test_basic_url_mapping
    env = { "BUNDLE_GEMFILE" => "#{__dir__}/url_map_test/Gemfile" }
    Dir.chdir("#{__dir__}/url_map_test") do
      server_spawn env: env
    end
    assert_equal "OK", send_http_read_resp_body("GET /ok HTTP/1.1\r\n\r\n")
  end
end
