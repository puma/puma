# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/svr_popen'

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# Other tests make use of 'client' SSLSockets created by net/http,
# and OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestPOpenSSL < ::TestPuma::SvrPOpen

  require 'openssl'

  # this checks an ssl binder configured with `ssl_bind` and also verifies that
  # OpenSSL is not loaded in Puma's process
  #
  def test_openssl_not_loaded
    skip_unless :mri
    skip 'Skip old Windows' if ::Puma.windows? && RUBY_VERSION < '2.4'
    setup_puma :ssl, config: <<RUBY
app do |env|
  ssl = env['rack.url_scheme'] + ' ' + (Object.const_defined? :OpenSSL).to_s
  [200, {}, [ssl]]
end
RUBY

    ctrl_type :tcp
    start_puma '-q'
    assert_equal 'https false', connect_get_body
  end

  def test_persistent_close
    puma_threads '5:5'
    threads = 10
    clients_per_thread = 2
    req_per_client = 1
    dly_client = 1.5
    dly_thread = dly_client/threads.to_f
    ctrl_type :tcp

    setup_puma :ssl, config: <<RUBY
persistent_timeout 1
RUBY
    start_puma '-q test/rackup/ci_string.ru'
    get_worker_pids if @puma_workers
    replies = {}

    client_threads = create_clients replies, threads, clients_per_thread,
       req_per_client: req_per_client, dly_client: dly_client, dly_thread: dly_thread

    client_threads.each(&:join)

    $debugging_info << "#{full_name}\n#{replies_info replies}\n"
    $debugging_info << "#{replies_time_info replies, threads, clients_per_thread, req_per_client}\n\n"

    ms = Puma::IS_MRI ? 60 : 140

    assert_equal threads*clients_per_thread*req_per_client, replies[:times].length
    assert_operator replies[:times_summary][0.6], :<, ms
  end
end if ::Puma.ssl?
