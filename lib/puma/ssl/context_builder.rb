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

        #ctx.key_password_command = params['key_password_command'] if params['key_password_command']

        key = if params['key']
                File.open(params['key'])
              elsif params['key_pem']
                params['key_pem']
              else
                log_writer.error "Please specify the SSL key via 'key=' or 'key_pem='"
              end
        ctx.key = OpenSSL::PKey.read(key, key_password(params['key_password_command']))

        if params['cert'].nil? && params['cert_pem'].nil?
        end

        cert = if params['cert']
          File.binread(params['cert'])
        elsif params['cert_pem']
          params['cert_pem']
        else
          log_writer.error "Please specify the SSL cert via 'cert=' or 'cert_pem='"
        end
        ctx.cert = OpenSSL::X509::Certificate.new(cert)

        #if ['peer', 'force_peer'].include?(params['verify_mode'])
          #unless params['ca']
            #log_writer.error "Please specify the SSL ca via 'ca='"
          #end
          ## needed for Puma::MiniSSL::Socket#peercert, env['puma.peercert']
          #require 'openssl'
        #end

        #ctx.ca = params['ca'] if params['ca']
        #ctx.ssl_cipher_filter = params['ssl_cipher_filter'] if params['ssl_cipher_filter']
        #ctx.ssl_ciphersuites = params['ssl_ciphersuites'] if params['ssl_ciphersuites'] && HAS_TLS1_3

        #ctx.reuse = params['reuse'] if params['reuse']

        #ctx.no_tlsv1   = params['no_tlsv1'] == 'true'
        #ctx.no_tlsv1_1 = params['no_tlsv1_1'] == 'true'

        ctx.verify_mode = OpenSSL::SSL::VERIFY_NONE # TODO I believe this can be removed.
        #if params['verify_mode']
          #ctx.verify_mode = case params['verify_mode']
                            #when "peer"
                              #MiniSSL::VERIFY_PEER
                            #when "force_peer"
                              #MiniSSL::VERIFY_PEER | MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT
                            #when "none"
                              #MiniSSL::VERIFY_NONE
                            #else
                              #log_writer.error "Please specify a valid verify_mode="
                              #MiniSSL::VERIFY_NONE
                            #end
        #end

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
