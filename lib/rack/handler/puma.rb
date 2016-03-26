require 'rack/handler'
require 'puma'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {
        :Verbose => false,
        :Silent  => false
      }

      def self.run(app, options = {})
        options  = DEFAULT_OPTIONS.merge(options)

        conf = ::Puma::Configuration.new(options) do |c|
          c.quiet

          if options.delete(:Verbose)
            app = Rack::CommonLogger.new(app, STDOUT)
          end

          if options[:environment]
            c.environment options[:environment]
          end

          if options[:Threads]
            min, max = options.delete(:Threads).split(':', 2)
            c.threads min, max
          end

          host = options[:Host]

          if host && (host[0,1] == '.' || host[0,1] == '/')
            c.bind "unix://#{host}"
          else
            host ||= ::Puma::Configuration::DefaultTCPHost
            port = options[:Port] || ::Puma::Configuration::DefaultTCPPort

            c.port port, host
          end

          c.app app
        end

        events = options.delete(:Silent) ? ::Puma::Events.strings : ::Puma::Events.stdio

        launcher = ::Puma::Launcher.new(conf, :events => events)

        yield launcher if block_given?
        begin
          launcher.run
        rescue Interrupt
          puts "* Gracefully stopping, waiting for requests to finish"
          launcher.stop
          puts "* Goodbye!"
        end
      end

      def self.valid_options
        {
          "Host=HOST"       => "Hostname to listen on (default: localhost)",
          "Port=PORT"       => "Port to listen on (default: 8080)",
          "Threads=MIN:MAX" => "min:max threads to use (default 0:16)",
          "Verbose"         => "Don't report each request (default: false)"
        }
      end
    end

    register :puma, Puma
  end
end
