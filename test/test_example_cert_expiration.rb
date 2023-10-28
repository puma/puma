# frozen_string_literal: true

require_relative 'helper'

require 'openssl'

#
# Thes are tests to ensure that the checked in certs in the ./examples/
# directory are valid and work as expected.
#
# These tets will start to fail 1 month before the certs expire
#
class TestExampleCertExpiration < Minitest::Test
  EXAMPLES_DIR = File.expand_path '../examples', __dir__
  EXPIRE_THRESHOLD = Time.now.utc - (60 * 60 * 24 * 30) # 30 days

  # Explicitly list the files to test
  TEST_FILES = %w[
    puma/cert_puma.pem
    puma/client-certs/client.crt
    puma/client-certs/ca.crt
    puma/client-certs/client_unknown.crt
    puma/client-certs/server.crt
    puma/client-certs/unknown_ca.crt
    puma/chain_cert/ca.crt
    puma/chain_cert/cert.crt
    puma/chain_cert/intermediate.crt
  ]

  # TODO: Add these files to the list above if they are not supposed to be expired
  # CA/newcerts/cert_1.pem
  # CA/newcerts/cert_2.pem
  # CA/cacert.pem

  def test_certs_not_expired
    TEST_FILES.each do |path|
      full_path  = File.join(EXAMPLES_DIR, path)
      cert       = OpenSSL::X509::Certificate.new File.read(full_path)
      parent_dir = File.dirname(path)

      msg = "Cert #{path} has expired. Check the #{parent_dir} for a `.rb` with instructions on how to regenerate."

      assert(cert.not_after > EXPIRE_THRESHOLD, msg)
    end
  end
end
