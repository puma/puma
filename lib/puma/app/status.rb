module Puma
  module App
    class Status
      def initialize(server, cli)
        @server = server
        @cli = cli
      end

      def call(env)
        case env['PATH_INFO']
        when "/stop"
          @server.stop
          return [200, {}, ['{ "status": "ok" }']]

        when "/halt"
          @server.halt
          return [200, {}, ['{ "status": "ok" }']]

        when "/restart"
          if @cli and @cli.restart_on_stop!
            @server.stop
            return [200, {}, ['{ "status": "ok" }']]
          else
            return [200, {}, ['{ "status": "not configured" }']]
          end

        when "/stats"
          b = @server.backlog
          r = @server.running
          return [200, {}, ["{ \"backlog\": #{b}, \"running\": #{r} }"]]
        end

        [404, {}, ["Unsupported action"]]
      end
    end
  end
end
