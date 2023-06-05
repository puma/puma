# frozen_string_literal: true

=begin
regenerates ca.pem, ca_keypair.pem,
            subca.pem, subca_keypair.pem,
            cert.pem, cert_keypair.pem
            ca_chain.pem,
            cert_chain.pem

certs before date will be the first of the current month

expires in 4 years

=end

require 'certificate_authority'

module Generate

  CA = "ca.pem"
  CA_KEY = "ca_keypair.pem"

  INTERMEDIATE = "intermediate.pem"
  SUB_CA_KEY = "intermediate.pem"

  CA_CHAIN = "ca_chain.pem"

  CERT = "cert.crt"
  CERT_KEY = "cert_keypair.pem"

  CERT_CHAIN = "cert_chain.pem"

  class << self

    def path
      File.expand_path(__dir__)
    end

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

    require 'debug'
    def run
      cert = generate_cert

      Dir.chdir path do
        File.write "ca.pem", root_ca.to_pem, mode: 'wb'
        File.write "ca_keypair.pem", root_ca.key_material.private_key.to_pem, mode: 'wb'

        File.write "intermediate.pem", intermediate_ca.to_pem, mode: 'wb'
        File.write "intermediate_keypair.pem", intermediate_ca.key_material.private_key.to_pem, mode: 'wb'

        File.write "cert.pem", cert.to_pem, mode: 'wb'
        File.write "cert_keypair.pem", cert.key_material.private_key.to_pem, mode: 'wb'

        ca_chain = intermediate_ca.to_pem + root_ca.to_pem
        File.write "ca_chain.pem", ca_chain, mode: 'wb'

        cert_chain = cert.to_pem + ca_chain
        File.write "cert_chain.pem", cert_chain, mode: 'wb'
      end

    rescue => e
        puts "error: #{e.message}"
    end
  end
end

Generate.run
