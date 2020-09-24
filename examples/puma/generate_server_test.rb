# frozen_string_literal: true

=begin
regenerates cert_puma.pem and puma_keypair.pem
dates, key length & sign_algorithm are changed

JRuby:
after running this file, delete server.p12 and keystore.jks, then (I think)
cd examples/puma
openssl pkcs12 -export -password pass:jruby_puma -inkey puma_keypair.pem -in cert_puma.pem -name puma -out server.p12
keytool -importkeystore -srckeystore server.p12 -srcstoretype pkcs12 -srcstorepass jruby_puma -destkeystore keystore.jks -deststoretype JKS -storepass jruby_puma
=end

require 'openssl'

module Generate

  KEY_LEN = 2048
  SIGN_ALGORITHM = OpenSSL::Digest::SHA256

  FNC = 'cert_puma.pem'
  FNK = 'puma_keypair.pem'

  class << self

    def run
      ca_key = OpenSSL::PKey::RSA.new KEY_LEN
      key    = OpenSSL::PKey::RSA.new KEY_LEN

      raw = File.read File.join(__dir__, FNC), mode: 'rb'

      cert = OpenSSL::X509::Certificate.new raw
      puts "\nOld:", cert.to_text, ""

      now = Time.now.utc
      mo = now.month
      yr = now.year
      zone = '+00:00'

      cert.not_before = Time.new yr  , mo, 1, 0, 0, 0, zone
      cert.not_after  = Time.new yr+4, mo, 1, 0, 0, 0, zone
      cert.public_key = key.public_key
      cert.sign ca_key, SIGN_ALGORITHM.new
      puts "New:", cert.to_text, ""

      Dir.chdir __dir__ do
        File.write FNC, cert.to_pem, mode: 'wb'
        File.write FNK, key.to_pem , mode: 'wb'
      end
    rescue => e
        puts "error: #{e.message}"
    end
  end
end

Generate.run
