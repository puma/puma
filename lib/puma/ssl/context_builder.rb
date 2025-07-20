require 'openssl'

module Puma
  module SSL
    class ContextBuilder
      def initialize(params, log_writer)
        @params = params
        @log_writer = log_writer
      end

      def context
        ctx = OpenSSL::SSL::SSLContext.new

        if params['key'].nil? && params['key_pem'].nil?
          log_writer.error "Please specify the SSL key via 'key=' or 'key_pem='"
        end

        #ctx.key = params['key'] if params['key']
        #ctx.key_pem = params['key_pem'] if params['key_pem']
        #ctx.key_password_command = params['key_password_command'] if params['key_password_command']

        # TODO also handle params['key_pem']
        key = OpenSSL::PKey.read(File.open(params['key']))

        if params['cert'].nil? && params['cert_pem'].nil?
          log_writer.error "Please specify the SSL cert via 'cert=' or 'cert_pem='"
        end

        # TODO handle also params['cert_pem']
        cert = OpenSSL::X509::Certificate.new(File.binread(params['cert']))

        #ctx.add_certificate(cert, key)
        ctx.cert = cert
        ctx.key = key

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
    end
  end
end
