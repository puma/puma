# frozen_string_literal: true

require 'json'

module Puma
  module App
    # Check out {#call}'s source code to see what actions this web application
    # can respond to.
    class Status
      OK_STATUS = '{ "status": "ok" }'.freeze

      def initialize(cli, control_auth_token = nil, status_auth_token = nil)
        @cli = cli
        @control_token = control_auth_token
        @status_token = status_auth_token
      end

      def call(env)
        case env['PATH_INFO']

        # Actions requiring the control token, if specified.

        when /\/stop$/
          return invalid_token('stop') unless authenticate_control(env)
          @cli.stop
          rack_response(200, OK_STATUS)

        when /\/halt$/
          return invalid_token('halt') unless authenticate_control(env)
          @cli.halt
          rack_response(200, OK_STATUS)

        when /\/restart$/
          return invalid_token('restart') unless authenticate_control(env)
          @cli.restart
          rack_response(200, OK_STATUS)

        when /\/phased-restart$/
          return invalid_token('phased restart') unless authenticate_control(env)
          if !@cli.phased_restart
            rack_response(404, '{ "error": "phased_restart not available" }')
          else
            rack_response(200, OK_STATUS)
          end

        when /\/reload-worker-directory$/
          return invalid_token('reload worker directory') unless authenticate_control(env)
          if !@cli.send(:reload_worker_directory)
            rack_response(404, '{ "error": "reload_worker_directory not available" }')
          else
            rack_response(200, OK_STATUS)
          end

        when /\/gc$/
          return invalid_token('gc') unless authenticate_control(env)
          GC.start
          rack_response(200, OK_STATUS)

        # Actions requiring the control or status tokens, if specified.

        when /\/gc-stats$/
          return invalid_token('access gc stats') unless authenticate_status(env)
          rack_response(200, GC.stat.to_json)

        when /\/stats$/
          return invalid_token('access stats') unless authenticate_status(env)
          rack_response(200, @cli.stats)

        when /\/thread-backtraces$/
          return invalid_token('access thread backtraces') unless authenticate_status(env)
          backtraces = []
          @cli.thread_status do |name, backtrace|
            backtraces << { name: name, backtrace: backtrace }
          end
          rack_response(200, backtraces.to_json)

        # Require the control token, if specified, when responding to unsupported actions.

        else
          return invalid_token unless authenticate_control(env)
          rack_response 404, "Unsupported action", 'text/plain'
        end
      end

      private

      def authenticate(env, token)
        return true unless token
        env['QUERY_STRING'].to_s.split(/&;/).include?("token=#{token}")
      end

      def authenticate_control(env)
        authenticate(env, @control_token)
      end

      # The control token includes access to status actions.
      # But when no status token is defined, no token is needed, so the control token is not checked.

      def authenticate_status(env)
        authenticate(env, @status_token) || authenticate(env, @control_token)
      end

      def invalid_token(action = '')
        action = "to #{action}" if action
        rack_response(403, "Invalid auth token#{action}", 'text/plain')
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
