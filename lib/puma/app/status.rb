# frozen_string_literal: true

require 'json'

module Puma
  module App
    # Check out {#call}'s source code to see what actions this web application
    # can respond to.
    class Status
      OK_STATUS = '{ "status": "ok" }'.freeze

      def initialize(cli, token = nil, actions = [])
        @cli = cli
        @auth_token = token
        @auth_actions = actions
      end

      def call(env)
        unless authenticate(env)
          return rack_response(403, 'Invalid auth token', 'text/plain')
        end

        case env['PATH_INFO']
        when /\/(stop)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          @cli.stop
          rack_response(200, OK_STATUS)

        when /\/(halt)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          @cli.halt
          rack_response(200, OK_STATUS)

        when /\/(restart)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          @cli.restart
          rack_response(200, OK_STATUS)

        when /\/(phased-restart)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          if !@cli.phased_restart
            rack_response(404, '{ "error": "phased restart not available" }')
          else
            rack_response(200, OK_STATUS)
          end

        when /\/(reload-worker-directory)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          if !@cli.send(:reload_worker_directory)
            rack_response(404, '{ "error": "reload_worker_directory not available" }')
          else
            rack_response(200, OK_STATUS)
          end

        when /\/(gc)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          GC.start
          rack_response(200, OK_STATUS)

        when /\/(gc-stats)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          rack_response(200, GC.stat.to_json)

        when /\/(stats)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          rack_response(200, @cli.stats)

        when /\/(thread-backtraces)$/
          action = $1
          return not_authorized(action) unless authorized(action)
          backtraces = []
          @cli.thread_status do |name, backtrace|
            backtraces << { name: name, backtrace: backtrace }
          end
          rack_response(200, backtraces.to_json)

        else
          rack_response 404, "Unsupported action", 'text/plain'
        end
      end

      private

      def authenticate(env)
        return true unless @auth_token
        env['QUERY_STRING'].to_s.split(/&;/).include?("token=#{@auth_token}")
      end

      def authorized(action)
        return true if @auth_actions.empty?
        @auth_actions.include? action
      end

      def not_authorized(action)
        rack_response(401, "Action '#{action}' not authorized", 'text/plain')
      end

      def rack_response(status, body, content_type='application/json')
        headers = {
          'Content-Type' => content_type,
          'Content-Length' => body.bytesize.to_s
        }

        [status, headers, [body]]
      end
    end
  end
end
