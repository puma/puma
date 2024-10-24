# frozen_string_literal: false

=begin
run code to generate all certs
certs before date will be the first of the current month
=end

require "openssl"

module GenerateClientCerts

  KEY_LEN = 2048
  SIGN_ALGORITHM = OpenSSL::Digest::SHA256

  CA_EXTS = [
    ["basicConstraints","CA:TRUE",true],
    ["keyUsage","cRLSign,keyCertSign",true],
  ]
  EE_EXTS = [
    #["keyUsage","keyEncipherment,digitalSignature",true],
    ["keyUsage","keyEncipherment,dataEncipherment,digitalSignature",true],
  ]

  class << self
    def run
      set_dates
      output_info
      setup_issue
      write_files
    rescue => e
      puts "error: #{e.message}"
      exit 1
    end

    private

    def setup_issue
      ca    = OpenSSL::X509::Name.parse "/DC=net/DC=puma/CN=CA"
      ca_u  = OpenSSL::X509::Name.parse "/DC=net/DC=puma/CN=CAU"
      svr   = OpenSSL::X509::Name.parse "/DC=net/DC=puma/CN=localhost"
      cli   = OpenSSL::X509::Name.parse "/DC=net/DC=puma/CN=localhost"
      cli_u = OpenSSL::X509::Name.parse "/DC=net/DC=puma/CN=localhost"

      [:@ca_key, :@svr_key, :@cli_key, :@ca_key_u, :@cli_key_u].each do |k|
        instance_variable_set k, OpenSSL::PKey::RSA.generate(KEY_LEN)
      end

      @ca_cert  = issue_cert ca , @ca_key ,  3, @before, @after, CA_EXTS, nil     , nil    , SIGN_ALGORITHM.new
      @svr_cert = issue_cert svr, @svr_key,  7, @before, @after, EE_EXTS, @ca_cert, @ca_key, SIGN_ALGORITHM.new
      @cli_cert = issue_cert cli, @cli_key, 11, @before, @after, EE_EXTS, @ca_cert, @ca_key, SIGN_ALGORITHM.new

      # unknown certs
      @ca_cert_u  = issue_cert ca_u , @ca_key_u , 17, @before, @after, CA_EXTS, nil       , nil      , SIGN_ALGORITHM.new
      @cli_cert_u = issue_cert cli_u, @cli_key_u, 19, @before, @after, EE_EXTS, @ca_cert_u, @ca_key_u, SIGN_ALGORITHM.new

      # expired cert is identical to client cert with different dates
      @cli_cert_exp = issue_cert cli, @cli_key, 23, @b_exp, @a_exp, EE_EXTS, @ca_cert, @ca_key, SIGN_ALGORITHM.new
    end

    def issue_cert(dn, key, serial, not_before, not_after, extensions, issuer, issuer_key, digest)
      cert = OpenSSL::X509::Certificate.new
      issuer = cert unless issuer
      issuer_key = key unless issuer_key
      cert.version = 2
      cert.serial = serial
      cert.subject = dn
      cert.issuer = issuer.subject
      cert.public_key = key.public_key
      cert.not_before = not_before
      cert.not_after = not_after
      ef = OpenSSL::X509::ExtensionFactory.new
      ef.subject_certificate = cert
      ef.issuer_certificate = issuer
      extensions.each { |oid, value, critical|
        cert.add_extension(ef.create_extension(oid, value, critical))
      }
      cert.sign(issuer_key, digest)
      cert
    end

    def write_files
      path = "#{__dir__}/puma/client_certs"

      Dir.chdir path do
        File.write "ca.crt"    , @ca_cert.to_pem , mode: 'wb'
        File.write "ca.key"    , @ca_key.to_pem  , mode: 'wb'
        File.write "server.crt", @svr_cert.to_pem, mode: 'wb'
        File.write "server.key", @svr_key.to_pem , mode: 'wb'
        File.write "client.crt", @cli_cert.to_pem, mode: 'wb'
        File.write "client.key", @cli_key.to_pem , mode: 'wb'

        File.write "unknown_ca.crt", @ca_cert_u.to_pem, mode: 'wb'
        File.write "unknown_ca.key", @ca_key_u.to_pem , mode: 'wb'

        File.write "client_unknown.crt", @cli_cert_u.to_pem, mode: 'wb'
        File.write "client_unknown.key", @cli_key_u.to_pem , mode: 'wb'

        File.write "client_expired.crt", @cli_cert_exp.to_pem, mode: 'wb'
        File.write "client_expired.key", @cli_key.to_pem     , mode: 'wb'
      end
    end

    def set_dates
      now = Time.now.utc
      mo = now.month
      yr = now.year
      zone = '+00:00'

      @before = Time.new yr  , mo, 1, 0, 0, 0, zone
      @after  = Time.new yr+4, mo, 1, 0, 0, 0, zone

      @b_exp  = Time.new yr-1, mo, 1, 0, 0, 0, zone
      @a_exp  = Time.new yr  , mo, 1, 0, 0, 0, zone
    end

    def output_info
      puts <<~INFO
            Key length: #{KEY_LEN}
        sign_algorithm: #{SIGN_ALGORITHM}

        Normal cert dates:  #{@before} to #{@after}

        Expired cert dates: #{@b_exp} to #{@a_exp}
      INFO
    end
  end
end

GenerateClientCerts.run
