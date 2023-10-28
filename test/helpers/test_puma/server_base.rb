# frozen_string_literal: true

require "puma/control_cli"
require "puma/dsl"
require "json"

require_relative "../test_puma"
require_relative "puma_socket"

module TestPuma

  # Base class for `TestPuma::ServerSpawn` and `TestPuma::ServerInProcess`.
  # It contains methods that:
  # * setup socket parameters (both listeners and control)
  # * return strings for use in CLI arguments and/or config files
  # * assist in setting SSL connection parameters
  #
  # The variables set here are used by `TestPuma:PumaSocket` for client request
  # setup.

  class ServerBase < Minitest::Test
    include TestPuma
    include TestPuma::PumaSocket

    HELLO_RU = "test/rackup/hello.ru"

    #————————————————————————————————————————————————————————————— SSL constants
    CERT_PATH = File.expand_path "../../../examples/puma/", __dir__
    CLIENT_CERTS_PATH = "#{CERT_PATH}/client-certs"

    DFLT_SSL_QUERY = if Puma::IS_JRUBY
      { keystore: "#{CERT_PATH}/keystore.jks",
        keystore_pass: "jruby_puma"
      }
    else
      { key:  "#{CERT_PATH}/puma_keypair.pem",
        cert: "#{CERT_PATH}/cert_puma.pem"
      }
    end

    if Puma::HAS_SSL
      MINI_VERIFY_PEER = ::Puma::MiniSSL::VERIFY_PEER
      MINI_FORCE_PEER  = ::Puma::MiniSSL::VERIFY_PEER | ::Puma::MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT
      MINI_VERIFY_NONE = ::Puma::MiniSSL::VERIFY_NONE
      HAS_TLS_1_3 = OpenSSL::SSL.const_defined? :TLS1_3_VERSION
    end

    def before_setup
      super
      @config_path = nil
      @server = nil
      @state_path = nil
      @workers = nil
      @spawn_ext_pids = []
    end

    def after_teardown
      @spawn_ext_pids.each { |pid| kill_and_wait pid }
      super
    end

    def set_bind_type(type, host: nil)
      @bind_host = host if host
      case type
      when :aunix, :unix
        skip_unless type
        @bind_type = type
      when :ssl
        skip_unless :ssl
        @bind_type = :ssl
      when :tcp
        @bind_type = :tcp
      else
        raise ArgumentError, "Invalid bind type #{type.inspect}, must be one of :aunix, :ssl, :tcp, :unix"
      end
    end

    def set_control_type(type, host: nil)
      @control_host = host if host
      case type
      when :aunix, :unix
        skip_unless type
        @control_type = type
      when :ssl
        skip_unless :ssl
        @control_type = :ssl
      when :tcp
        @control_type = :tcp
      else
        raise ArgumentError, "Invalid control type #{type.inspect}, must be one of :aunix, :ssl, :tcp, :unix"
      end
    end

    def bind_host
      @bind_host ||= HOST
    end

    def bind_path
      @bind_path ||= @bind_type == :aunix ?
        "@#{File.basename unique_path(['bind_', '.sock'])}" :
        unique_path(['bind_', '.sock'])
    end

    def bind_port
      @bind_port ||= unique_port bind_host
    end

    def control_host
      @control_host ||= HOST
    end

    def control_path
      @control_path ||= @control_type == :aunix ?
        "@#{File.basename unique_path(['ctrl_', '.sock'])}" :
        unique_path(['ctrl_', '.sock'])
    end

    def control_port
      @control_port ||= unique_port control_host
    end

    def set_bind_ssl(**opts)
      host = opts.delete(:host) || bind_host
      port = opts.delete(:port) || bind_port
      @bind_ssl = Puma::DSL.ssl_bind_str host, port, opts
    end

    def bind_ssl(**opts)
      @bind_ssl ||= set_bind_ssl(**DFLT_SSL_QUERY.merge(opts))
    end

    def set_control_ssl(hash)
      @control_ssl = Puma::DSL.ssl_bind_str control_host, control_port, hash
    end

    def control_ssl
      @control_ssl ||= set_control_ssl DFLT_SSL_QUERY
    end

    def bind_uri_str
      case @bind_type
      when :ssl
        bind_ssl
      when :tcp
        "tcp://#{bind_host}:#{bind_port}"
      when :aunix, :unix
        "unix://#{bind_path}"
      end
    end

    def control_uri_str
      case @control_type
      when :ssl
        control_ssl
      when :tcp
        "tcp://#{control_host}:#{control_port}"
      when :unix
        "unix://#{control_path}"
      end
    end

    # Returns arguments used in a command line string to create or use a
    # Puma control server
    def set_pumactl_args
      # Used in both `Puma::CLI` and `Puma::ControlCLI`
      "--control-url #{control_uri_str} --control-token #{TOKEN}"
    end

    # returns the line used in a Puma configuration file to create a control server
    def control_config_str
      case @control_type
      when :tcp
        "activate_control_app 'tcp://#{control_host}:#{control_port}', auth_token: '#{TOKEN}'"
      when :unix
        "activate_control_app 'unix://#{control_path}', auth_token: '#{TOKEN}'"
      end
    end

    def config_path(contents = nil)
      if contents
        @config_path ||= unique_path %w[config_ .rb], contents: contents
      else
        @config_path
      end
    end

    def state_path
      @state_path ||= unique_path '.state'
    end

    def set_workers(count)
      @workers = count
    end

    def workers
      @workers ||= 0
    end
  end

  def spawn_ext_cmd(env = {}, cmd)
    opts = {}

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    out_r.binmode
    err_r.binmode

    pid = spawn(env, cmd, opts)
    @spawn_ext_pids << pid
    [out_w, err_w].each(&:close)
    @ios_to_close << out_r << err_r
    [out_r, err_r, pid]
  end

  def curl_and_get_response(url, method: :get, args: nil)
    cmd = "curl -s -v --show-error #{args} -X #{method.to_s.upcase} -k #{url}"

    out_r, err_r, _ = spawn_ext_cmd cmd

    out_r.wait_readable 3

    err = err_r.read
    out = out_r.read

    http_status = err[/< (HTTP\/1.1 \d+ [A-Z ]+)/, 1] # < HTTP/1.1 200 OK

    assert_equal "HTTP/1.1 200 OK", http_status, "Incorrect HTTP status\n#{err}\n"

    out
  end
end
