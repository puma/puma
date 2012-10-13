module Puma
  module App
    class Status
      def initialize(server, cli)
        @server = server
        @cli = cli
        @auth_token = nil
      end
      OK_STATUS = '{ "status": "ok" }'.freeze

      attr_accessor :auth_token

      def authenticate(env)
        return true unless @auth_token
        env['QUERY_STRING'].to_s.split(/&;/).include?("token=#{@auth_token}")
      end

      def call(env)
        unless authenticate(env)
          return rack_response(403, 'Invalid auth token', 'text/plain')
        end

        case env['PATH_INFO']
        when /\/stop$/
          @server.stop
          return rack_response(200, OK_STATUS)

        when /\/halt$/
          @server.halt
          return rack_response(200, OK_STATUS)

        when /\/restart$/
          if @cli and @cli.restart_on_stop!
            @server.begin_restart

            return rack_response(200, OK_STATUS)
          else
            return rack_response(200, '{ "status": "not configured" }')
          end

        when /\/stats$/
          b = @server.backlog
          r = @server.running
          return rack_response(200, %Q!{ "backlog": #{b}, "running": #{r} }!)
        end

        rack_response 404, "Unsupported action", 'text/plain'
      end

      private
      def rack_response(status, body, content_type='application/json')
        [status, { 'Content-Type' => content_type, 'Content-Length' => body.bytesize.to_s }, [body]]
      end
    end
  end
end
