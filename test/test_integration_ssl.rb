# frozen_string_literal: true

require_relative 'helper'
require_relative "helpers/test_puma/server_spawn"

if ::Puma::HAS_SSL # don't load any files if no ssl support
  require "openssl"
  require_relative "helpers/test_puma/puma_socket"
end

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSocketss, so OpenSSL
# is loaded in the CI process.  By shelling out with spawn, the server process
# isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSL < TestPuma::ServerSpawn
  parallelize_me! if ::Puma::IS_MRI

  def setup
    set_bind_type :ssl
    set_control_type :tcp
  end

  def test_ssl_run_cli
    # windows won't parse the CLI ssl bind properly
    skip_if :windows
    server_spawn "-q -t1:5 test/rackup/url_scheme.ru"

    assert_equal "https", send_http_read_resp_body
  end

  def test_ssl_run_config
    server_spawn "-q -t1:5 test/rackup/url_scheme.ru", no_bind: true,
      config: "bind '#{bind_uri_str}'"

    assert_equal "https", send_http_read_resp_body
  end

  def test_ssl_run_with_localhost_authority
    skip_if :jruby

    server_spawn no_bind: true, config: <<~CONFIG
      require 'localhost'
      ssl_bind '#{LOCALHOST}', '#{bind_port}'

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    CONFIG

    assert_equal "https", send_http_read_resp_body
  end
end if ::Puma::HAS_SSL
