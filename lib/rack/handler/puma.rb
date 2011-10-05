require 'rack/handler'
require 'puma'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {:Host => '0.0.0.0', :Port => 8080, :Threads => '0:16'}

      def self.run(app, options = {})
        options  = DEFAULT_OPTIONS.merge(options)
        server   = ::Puma::Server.new(app)
        min, max = options[:Threads].split(':', 2)

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
          "Threads=MIN:MAX" => "min:max threads to use (default 0:16)"
        }
      end
    end

    register :puma, Puma
  end
end
