require 'rack/handler'
require 'puma'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {
        :Host => '0.0.0.0',
        :Port => 8080,
        :Threads => '0:16',
        :Quiet => false
      }

      def self.run(app, options = {})
        options  = DEFAULT_OPTIONS.merge(options)

        unless options[:Quiet]
          app = Rack::CommonLogger.new(app, STDOUT)
        end

        server   = ::Puma::Server.new(app)
        min, max = options[:Threads].split(':', 2)

        puts "Puma #{::Puma::Const::PUMA_VERSION} starting..."
        puts "* Min threads: #{min}, max threads: #{max}"
        puts "* Listening on tcp://#{options[:Host]}:#{options[:Port]}"

        server.add_tcp_listener options[:Host], options[:Port]
        server.min_threads = Integer(min)
        server.max_threads = Integer(max)
        yield server if block_given?

        server.run.join
      end

      def self.valid_options
        {
          "Host=HOST"       => "Hostname to listen on (default: localhost)",
          "Port=PORT"       => "Port to listen on (default: 8080)",
          "Threads=MIN:MAX" => "min:max threads to use (default 0:16)",
          "Quiet"           => "Don't report each request"
        }
      end
    end

    register :puma, Puma
  end
end
