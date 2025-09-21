require 'openssl'
require 'open3'

module Puma
  module SSL
    class ContextBuilder
      def initialize(params, log_writer)
        @params = params
        @log_writer = log_writer
      end

      def context
        ctx = OpenSSL::SSL::SSLContext.new

        key = if params['key']
                File.open(params['key'])
              elsif params['key_pem']
                params['key_pem']
              else
                log_writer.error "Please specify the SSL key via 'key=' or 'key_pem='"
              end
        ctx.key = OpenSSL::PKey.read(key, key_password(params['key_password_command']))

        cert = if params['cert']
          File.binread(params['cert'])
        elsif params['cert_pem']
          params['cert_pem']
        else
          log_writer.error "Please specify the SSL cert via 'cert=' or 'cert_pem='"
        end
        ctx.cert = OpenSSL::X509::Certificate.new(cert)

        #ctx.ssl_cipher_filter = params['ssl_cipher_filter'] if params['ssl_cipher_filter']
        #ctx.ssl_ciphersuites = params['ssl_ciphersuites'] if params['ssl_ciphersuites'] && HAS_TLS1_3

        #ctx.reuse = params['reuse'] if params['reuse']

        #ctx.no_tlsv1   = params['no_tlsv1'] == 'true'
        #ctx.no_tlsv1_1 = params['no_tlsv1_1'] == 'true'

        # TODO figure out why params['ca'] is an empty string
        ca = params['ca'] && !params['ca'].empty? ? params['ca'] : nil
        if ['peer', 'force_peer'].include?(params['verify_mode']) && !ca
          log_writer.error "Please specify the SSL ca via 'ca='"
        end
        if ca
          cert_store = OpenSSL::X509::Store.new
          cert_store.add_file ca
          ctx.cert_store = cert_store
        end

        if params['verify_mode']
          ctx.verify_mode = case params['verify_mode']
                            when "peer"
                              OpenSSL::SSL::VERIFY_PEER
                            when "force_peer"
                              OpenSSL::SSL::VERIFY_PEER | OpenSSL::SSL::VERIFY_FAIL_IF_NO_PEER_CERT
                            when "none"
                              OpenSSL::SSL::VERIFY_NONE
                            else
                              log_writer.error "Please specify a valid verify_mode="
                              OpenSSL::SSL::VERIFY_NONE
                            end
        end

        #if params['verification_flags']
          #ctx.verification_flags = params['verification_flags'].split(',').
            #map { |flag| MiniSSL::VERIFICATION_FLAGS.fetch(flag) }.
            #inject { |sum, flag| sum ? sum | flag : flag }
        #end

        ctx
      end

      private

      attr_reader :params, :log_writer

      # Executes the command to return the password needed to decrypt the key.
      def key_password(command)
        return nil if command.nil?

        stdout_str, stderr_str, status = Open3.capture3(command)
        return stdout_str.chomp if status.success?

        raise "Key password failed with code #{status.exitstatus}: #{stderr_str}"
      end
    end
  end
end
