# frozen_string_literal: true

=begin
regenerates ca.pem, ca_keypair.pem,
            subca.pem, subca_keypair.pem,
            cert.pem, cert_keypair.pem
            ca_chain.pem,
            cert_chain.pem

certs before date will be the first of the current month
=end

require 'bundler/inline'
gemfile(true) do
  source 'https://rubygems.org'
  gem 'certificate_authority'
end

module GenerateChainCerts

  CA               = "ca.crt"
  CA_KEY           = "ca.key"
  INTERMEDIATE     = "intermediate.crt"
  INTERMEDIATE_KEY = "intermediate.key"
  CERT             = "cert.crt"
  CERT_KEY         = "cert.key"

  CA_CHAIN         = "ca_chain.pem"
  CERT_CHAIN       = "cert_chain.pem"

  class << self

     def before_after
      @before_after ||= (
        now = Time.now.utc
        mo = now.month
        yr = now.year
        zone = '+00:00'

        {
          not_before: Time.new(yr, mo, 1, 0, 0, 0, zone),
          not_after:  Time.new(yr+4, mo, 1, 0, 0, 0, zone)
        }
      )
    end

    def root_ca
      @root_ca ||= generate_ca
    end

    def intermediate_ca
      @intermediate_ca ||= generate_ca(common_name: "intermediate.puma.localhost", parent: root_ca)
    end

    def generate_ca(common_name: "ca.puma.localhost", parent: nil)
      ca = CertificateAuthority::Certificate.new

      ca.subject.common_name = common_name
      ca.signing_entity      = true
      ca.not_before          = before_after[:not_before]
      ca.not_after           = before_after[:not_after]

      ca.key_material.generate_key

      if parent
        ca.serial_number.number = parent.serial_number.number + 10
        ca.parent = parent
      else
        ca.serial_number.number = 1
      end

      signing_profile = {"extensions" => {"keyUsage" => {"usage" => ["critical", "keyCertSign"] }} }

      ca.sign!(signing_profile)

      ca
    end

    def generate_cert(common_name: "test.puma.localhost",  parent: intermediate_ca)

      cert = CertificateAuthority::Certificate.new

      cert.subject.common_name  = common_name
      cert.serial_number.number = parent.serial_number.number + 100
      cert.parent               = parent

      cert.key_material.generate_key
      cert.sign!

      cert
    end

    def run
      cert = generate_cert

      path = "#{__dir__}/puma/chain_cert"

      Dir.chdir path do
        File.write CA, root_ca.to_pem, mode: 'wb'
        File.write CA_KEY, root_ca.key_material.private_key.to_pem, mode: 'wb'

        File.write INTERMEDIATE, intermediate_ca.to_pem, mode: 'wb'
        File.write INTERMEDIATE_KEY, intermediate_ca.key_material.private_key.to_pem, mode: 'wb'

        File.write CERT, cert.to_pem, mode: 'wb'
        File.write CERT_KEY, cert.key_material.private_key.to_pem, mode: 'wb'

        ca_chain = intermediate_ca.to_pem + root_ca.to_pem
        File.write CA_CHAIN, ca_chain, mode: 'wb'

        cert_chain = cert.to_pem + ca_chain
        File.write CERT_CHAIN, cert_chain, mode: 'wb'
      end
    rescue => e
      puts "error: #{e.message}"
      exit 1
    end
  end
end

GenerateChainCerts.run
