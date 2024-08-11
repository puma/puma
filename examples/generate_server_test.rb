# frozen_string_literal: true

=begin
regenerates cert_puma.pem and puma_keypair.pem
dates, key length & sign_algorithm are changed
=end

require 'openssl'

module GenerateServerCerts

  KEY_LEN = 2048
  SIGN_ALGORITHM = OpenSSL::Digest::SHA256

  FNC = 'cert_puma.pem'
  FNK = 'puma_keypair.pem'

  class << self

    def run
      path = "#{__dir__}/puma"
      ca_key = OpenSSL::PKey::RSA.new KEY_LEN
      key    = OpenSSL::PKey::RSA.new KEY_LEN

      raw = File.read File.join(path, FNC), mode: 'rb'

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

      Dir.chdir path do
        File.write FNC, cert.to_pem, mode: 'wb'
        File.write FNK, key.to_pem , mode: 'wb'
      end
    rescue => e
      puts "error: #{e.message}"
      exit 1
    end
  end
end

GenerateServerCerts.run
