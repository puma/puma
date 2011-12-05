module Puma
  module App
    class Status
      def initialize(server)
        @server = server
      end

      def call(env)
        case env['PATH_INFO']
        when "/stop"
          @server.stop
          return [200, {}, ['{ "status": "ok" }']]

        when "/halt"
          @server.halt
          return [200, {}, ['{ "status": "ok" }']]

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
