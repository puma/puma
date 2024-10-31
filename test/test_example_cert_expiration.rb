require_relative 'helper'
require 'openssl'

#
# Thes are tests to ensure that the checked in certs in the ./examples/
# directory are valid and work as expected.
#
# These tests will start to fail 1 month before the certs expire
#
class TestExampleCertExpiration < Minitest::Test
  EXAMPLES_DIR = File.expand_path '../examples/puma', __dir__
  EXPIRE_THRESHOLD = Time.now.utc - (60 * 60 * 24 * 30) # 30 days

  # Explicitly list the files to test
  TEST_FILES = %w[
    cert_puma.pem
    client_certs/ca.crt
    client_certs/client.crt
    client_certs/client_unknown.crt
    client_certs/server.crt
    client_certs/unknown_ca.crt
    chain_cert/ca.crt
    chain_cert/cert.crt
    chain_cert/intermediate.crt
  ]

  def test_certs_not_expired
    expiration_data = TEST_FILES.map do |path|
      full_path  = File.join(EXAMPLES_DIR, path)
      not_after  = OpenSSL::X509::Certificate.new(File.read(full_path)).not_after
      [not_after, path]
    end

    failed = expiration_data.select { |ary| ary[0] <= EXPIRE_THRESHOLD }

    if failed.empty?
      assert true
    else
      msg = +"\n** The below certs in the 'examples/puma' folder are expiring soon.\n" \
        "   See 'examples/generate_all_certs.md' for instructions on how to regenerate.\n\n"
      failed.each do |ary|
        msg << "     #{ary[1]}\n"
      end
      assert false, msg
    end
  end
end
