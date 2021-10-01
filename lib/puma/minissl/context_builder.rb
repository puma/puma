module Puma
  module MiniSSL
    class ContextBuilder
      def initialize(params, events)
        @params = params
        @events = events
      end

      def localhost_authority
        @localhost_authority ||= Localhost::Authority.fetch if defined?(Localhost::Authority) && !Puma::IS_JRUBY
      end

      def localhost_authority_context
        return unless localhost_authority

        key_path, crt_path = if [:key_path, :certificate_path].all? { |m| localhost_authority.respond_to?(m) }
          [localhost_authority.key_path, localhost_authority.certificate_path]
        else
          local_certificates_path = File.expand_path("~/.localhost")
          [File.join(local_certificates_path, "localhost.key"), File.join(local_certificates_path, "localhost.crt")]
        end
      end

      def context
        ctx = MiniSSL::Context.new

        if defined?(JRUBY_VERSION)
          unless params['keystore']
            events.error "Please specify the Java keystore via 'keystore='"
          end

          ctx.keystore = params['keystore']

          unless params['keystore-pass']
            events.error "Please specify the Java keystore password  via 'keystore-pass='"
          end

          ctx.keystore_pass = params['keystore-pass']
          ctx.ssl_cipher_list = params['ssl_cipher_list'] if params['ssl_cipher_list']
        else
          unless params['key']
            if localhost_authority
              params['key'] = localhost_authority_context[0]
            else
              events.error "Please specify the SSL key via 'key='"
            end
          end

          ctx.key = params['key']

          unless params['cert']
            if localhost_authority
              params['cert'] = localhost_authority_context[1]
            else
              events.error "Please specify the SSL cert via 'cert='"
            end
          end

          ctx.cert = params['cert']

          if ['peer', 'force_peer'].include?(params['verify_mode'])
            unless params['ca']
              events.error "Please specify the SSL ca via 'ca='"
            end
          end

          ctx.ca = params['ca'] if params['ca']
          ctx.ssl_cipher_filter = params['ssl_cipher_filter'] if params['ssl_cipher_filter']
        end

        ctx.no_tlsv1 = true if params['no_tlsv1'] == 'true'
        ctx.no_tlsv1_1 = true if params['no_tlsv1_1'] == 'true'

        if params['verify_mode']
          ctx.verify_mode = case params['verify_mode']
                            when "peer"
                              MiniSSL::VERIFY_PEER
                            when "force_peer"
                              MiniSSL::VERIFY_PEER | MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT
                            when "none"
                              MiniSSL::VERIFY_NONE
                            else
                              events.error "Please specify a valid verify_mode="
                              MiniSSL::VERIFY_NONE
                            end
        end

        if params['verification_flags']
          ctx.verification_flags = params['verification_flags'].split(',').
            map { |flag| MiniSSL::VERIFICATION_FLAGS.fetch(flag) }.
            inject { |sum, flag| sum ? sum | flag : flag }
        end

        ctx
      end

      private

      attr_reader :params, :events
    end
  end
end
