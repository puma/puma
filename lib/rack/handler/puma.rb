require 'rack/handler'
require 'puma'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {
        :Host => '0.0.0.0',
        :Port => 8080,
        :Threads => '0:16',
        :Verbose => false
      }

      def self.run(app, options = {})
        options  = DEFAULT_OPTIONS.merge(options)

        if options[:Verbose]
          app = Rack::CommonLogger.new(app, STDOUT)
        end

        if options[:environment]
          ENV['RACK_ENV'] = options[:environment].to_s
        end

        server   = ::Puma::Server.new(app)
        min, max = options[:Threads].split(':', 2)

        puts "Puma #{::Puma::Const::PUMA_VERSION} starting..."
        puts "* Min threads: #{min}, max threads: #{max}"
        puts "* Environment: #{ENV['RACK_ENV']}"
        puts "* Listening on tcp://#{options[:Host]}:#{options[:Port]}"

        server.add_tcp_listener options[:Host], options[:Port]
        server.min_threads = min
        server.max_threads = max
        yield server if block_given?

        begin
          server.run.join
        rescue Interrupt
          puts "* Gracefully stopping, waiting for requests to finish"
          server.stop(true)
          puts "* Goodbye!"
        end

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

