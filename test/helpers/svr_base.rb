# frozen_string_literal: true

require 'securerandom'
require_relative '../helper'

module TestPuma
  class SvrBase < ::Minitest::Test

    BIND_TYPES = %i[none ssl tcp aunix unix]
    HOST   = '127.0.0.1'
    TOKEN  = 'PUMA'

    def setup
      @bind_type = nil
      @bind_path = nil
      @bind_port = nil
      @bind_ssl  = nil
      @server    = nil
      @ios_to_close = []
    end

    # sets and returns an opts hash for use with Puma::DSL.ssl_bind_str
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
