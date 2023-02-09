require_relative 'helper'
require_relative "helpers/integration"

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSockets created by
# net/http, OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSL < TestIntegration
  parallelize_me! if ::Puma.mri?

  require "net/http"
  require "openssl"

  def teardown
    @server.close if @server && !@server.closed?
    @server = nil
    super
  end

  def bind_port
    @bind_port ||= UniquePort.call
  end

  def control_tcp_port
    @control_tcp_port ||= UniquePort.call
  end

  def with_server(config)
    config_file = Tempfile.new %w(config .rb)
    config_file.write config
    config_file.close

    # start server
    cmd = "#{BASE} bin/puma -C #{config_file.path}"
    @server = IO.popen cmd, 'r'
    wait_for_server_to_boot
    @pid = @server.pid

    http = Net::HTTP.new HOST, bind_port
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    yield http

    # stop server
    sock = TCPSocket.new HOST, control_tcp_port
    @ios_to_close << sock
    sock.syswrite "GET /stop?token=#{TOKEN} HTTP/1.1\r\n\r\n"
    sock.read
    assert_match 'Goodbye!', @server.read
  end

  def test_ssl_run
    config = <<RUBY
if ::Puma.jruby?
  keystore =  '#{File.expand_path '../examples/puma/keystore.jks', __dir__}'
  keystore_pass = 'jruby_puma'

  ssl_bind '#{HOST}', '#{bind_port}', {
    keystore: keystore,
    keystore_pass:  keystore_pass,
    verify_mode: 'none'
  }
else
  key  = '#{File.expand_path '../examples/puma/puma_keypair.pem', __dir__}'
  cert = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'

  ssl_bind '#{HOST}', '#{bind_port}', {
    cert: cert,
    key:  key,
    verify_mode: 'none'
  }
end

activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY
    with_server(config) do |http|
      body = nil
      http.start do
        req = Net::HTTP::Get.new '/', {}
        http.request(req) { |resp| body = resp.body }
      end
      assert_equal 'https', body
    end
  end

  def test_ssl_run_with_curl_client
    skip_if :windows; require 'stringio'

    app = lambda { |_| [200, { 'Content-Type' => 'text/plain' }, ["HELLO", ' ', "THERE"]] }
    opts = {max_threads: 1}
    server = Puma::Server.new app, nil, opts
    if Puma.jruby?
      ssl_params = {
          'keystore'      => File.expand_path('../examples/puma/client-certs/keystore.jks', __dir__),
          'keystore-pass' => 'jruby_puma', # keystore includes server.p12 as well as ca.crt
      }
    else
      ssl_params = {
          'cert' => File.expand_path('../examples/puma/client-certs/server.crt', __dir__),
          'key'  => File.expand_path('../examples/puma/client-certs/server.key', __dir__),
          'ca'   => File.expand_path('../examples/puma/client-certs/ca.crt', __dir__),
      }
    end
    ssl_params['verify_mode'] = 'force_peer' # 'peer'
    out_err = StringIO.new
    ssl_context = Puma::MiniSSL::ContextBuilder.new(ssl_params, Puma::LogWriter.new(out_err, out_err)).context
    server.add_ssl_listener(HOST, bind_port, ssl_context)

    server.run(true)
    begin
      ca = File.expand_path('../examples/puma/client-certs/ca.crt', __dir__)
      cert = File.expand_path('../examples/puma/client-certs/client.crt', __dir__)
      key = File.expand_path('../examples/puma/client-certs/client.key', __dir__)
      # NOTE: JRuby used to end up in a hang with TLS peer verification enabled
      # it's easier to reproduce using an external client such as CURL (using net/http client the bug isn't triggered)
      # also the "hang", being buffering related, seems to showcase better with TLS 1.2 than 1.3
      body = curl_and_get_response "https://localhost:#{bind_port}",
                                   args: "--cacert #{ca} --cert #{cert} --key #{key} --tlsv1.2 --tls-max 1.2"

      warn out_err.string unless out_err.string.empty?
      assert_equal 'HELLO THERE', body
    ensure
      server.stop(true)
    end
    assert_equal '', out_err.string
  end

  def test_ssl_run_with_pem
    skip_if :jruby

    config = <<RUBY
  key_path  = '#{File.expand_path '../examples/puma/puma_keypair.pem', __dir__}'
  cert_path = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'

  ssl_bind '#{HOST}', '#{bind_port}', {
    cert_pem: File.read(cert_path),
    key_pem:  File.read(key_path),
    verify_mode: 'none'
  }

activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY

    with_server(config) do |http|
      body = nil
      http.start do
        req = Net::HTTP::Get.new '/', {}
        http.request(req) { |resp| body = resp.body }
      end
      assert_equal 'https', body
    end
  end

  def test_ssl_run_with_localhost_authority
    skip_if :jruby

    config = <<RUBY
  require 'localhost'
  ssl_bind '#{HOST}', '#{bind_port}'

activate_control_app 'tcp://#{HOST}:#{control_tcp_port}', { auth_token: '#{TOKEN}' }

app do |env|
  [200, {}, [env['rack.url_scheme']]]
end
RUBY

    with_server(config) do |http|
      body = nil
      http.start do
        req = Net::HTTP::Get.new '/', {}
        http.request(req) { |resp| body = resp.body }
      end
      assert_equal 'https', body
    end
  end

  def test_ssl_run_without_any_key_and_authority; require 'logger'
    skip_if :windows; require 'stringio'

    app = lambda { |_| [200, { 'Content-Type' => 'text/plain' }, ["HELLO", ' ', "THERE"]] }
    opts = {max_threads: 1}
    server = Puma::Server.new app, nil, opts
    if Puma.jruby?
      ssl_params = {
          'keystore'      => nil,
          'keystore-pass' => nil
      }
    else
      ssl_params = {
          'cert' => nil,
          'key'  => nil,
          'ca'   => nil,
      }
    end
    ssl_params['verify_mode'] = 'force_peer' # 'peer'
    out_err = StringIO.new
    Puma::MiniSSL::ContextBuilder.new(ssl_params, Logger.new(out_err)).context
    assert_match(/Please specify the SSL key via 'key=' or 'key_pem=', or require the 'localhost' gem in your Puma config for automatic self-signed certificates/, out_err.string)
    assert_match(/Please specify the SSL cert via 'cert=' or 'cert_pem='/, out_err.string)
    assert_match(/Please specify the SSL ca via 'ca='/, out_err.string)

  end

  private

  def curl_and_get_response(url, method: :get, args: nil); require 'open3'
    cmd = "curl -s -v --show-error #{args} -X #{method.to_s.upcase} -k #{url}"
    begin
      out, err, status = Open3.capture3(cmd)
    rescue Errno::ENOENT
      fail "curl not available, make sure curl binary is installed and available on $PATH"
    end

    if status.success?
      http_status = err.match(/< HTTP\/1.1 (.*?)/)[1] || '0' # < HTTP/1.1 200 OK\r\n
      if http_status.strip[0].to_i > 2
        warn out
        fail "#{cmd.inspect} unexpected response: #{http_status}\n\n#{err}"
      end
      return out
    else
      warn out
      fail "#{cmd.inspect} process failed: #{status}\n\n#{err}"
    end
  end

end if ::Puma::HAS_SSL
