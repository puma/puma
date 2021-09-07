# frozen_string_literal: true

require 'securerandom'
require_relative '../helper'

module TestPuma

  # Base class for `SvrInProc` and `SvrPOpen`.
  class SvrBase < ::Minitest::Test

    # available bind types
    # @todo `:none` is for listeners are defined in a config file, but may need
    #  more work
    BIND_TYPES = %i[none ssl tcp aunix unix]

    # default host for all operations using TestPuma system.  `ENV['TEST_PUMA_HOST']`
    # can be set to alternative host address, example `[::1]`
    HOST = ENV['TEST_PUMA_HOST'] || '127.0.0.1'

    # control token when using `Puma::ControlCLI`
    TOKEN = 'PUMA'

    # sets up instance variables
    def setup
      @bind_type = nil
      @bind_path = nil
      @bind_port = nil
      @bind_ssl  = nil
      @server    = nil
      @ios_to_close = []
    end

    # sets and returns an opts hash for use with Puma::DSL.ssl_bind_str
    # @return [Hash]
    def ssl_default_opts
      @ssl_opts ||= begin
        opts = {}
        if Puma.jruby?
          opts[:keystore] = File.expand_path '../../examples/puma/keystore.jks', __dir__
          opts[:keystore_pass] = 'jruby_puma'
          opts[:ssl_cipher_list] = 'TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
          opts
        else
          opts[:cert] = File.expand_path '../../examples/puma/cert_puma.pem', __dir__
          opts[:key]  = File.expand_path '../../examples/puma/puma_keypair.pem', __dir__
        end
        opts
      end
    end
  end
end
