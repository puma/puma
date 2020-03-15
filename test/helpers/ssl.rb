module SSLHelper
  def ssl_query
    @ssl_query ||= if Puma.jruby?
      @keystore = File.expand_path "../../../examples/puma/keystore.jks", __FILE__
      @ssl_cipher_list = "TLS_DHE_RSA_WITH_DES_CBC_SHA,TLS_DHE_RSA_WITH_3DES_EDE_CBC_SHA"
      "keystore=#{@keystore}&keystore-pass=pswd&ssl_cipher_list=#{@ssl_cipher_list}"
    else
      @cert = File.expand_path "../../../examples/puma/cert_puma.pem", __FILE__
      @key  = File.expand_path "../../../examples/puma/puma_keypair.pem", __FILE__
      "key=#{@key}&cert=#{@cert}"
    end
  end
end
