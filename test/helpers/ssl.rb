# frozen_string_literal: true

module SSLHelper
  def ssl_query
    @ssl_query ||= if Puma.jruby?
      @keystore = File.expand_path "../../examples/puma/keystore.jks", __dir__
      @ssl_cipher_list = "TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256"
      "keystore=#{@keystore}&keystore-pass=jruby_puma&ssl_cipher_list=#{@ssl_cipher_list}"
    else
      @cert = File.expand_path "../../examples/puma/cert_puma.pem", __dir__
      @key  = File.expand_path "../../examples/puma/puma_keypair.pem", __dir__
      "key=#{@key}&cert=#{@cert}"
    end
  end

  # sets and returns an opts hash for use with Puma::DSL.ssl_bind_str
  def ssl_opts
    @ssl_opts ||= if Puma.jruby?
      @ssl_opts = {}
      @ssl_opts[:keystore] = File.expand_path '../../examples/puma/keystore.jks', __dir__
      @ssl_opts[:keystore_pass] = 'jruby_puma'
      @ssl_opts[:ssl_cipher_list] = 'TLS_DHE_RSA_WITH_AES_128_CBC_SHA,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256'
    else
      @ssl_opts = {}
      @ssl_opts[:cert] = File.expand_path '../../examples/puma/cert_puma.pem', __dir__
      @ssl_opts[:key]  = File.expand_path '../../examples/puma/puma_keypair.pem', __dir__
    end
  end
end
