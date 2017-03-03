require 'rack/handler'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {
        :Verbose => false,
        :Silent  => false
      }

      def self.config(app, options = {})
        require 'puma/configuration'
        require 'puma/events'
        require 'puma/launcher'

        options = DEFAULT_OPTIONS.merge(options)

        conf = ::Puma::Configuration.new(options) do |user_config, file_config, default_config|
          user_config.quiet

          if options.delete(:Verbose)
            app = Rack::CommonLogger.new(app, STDOUT)
          end

          if options[:environment]
            user_config.environment options[:environment]
          end

          if options[:Threads]
            min, max = options.delete(:Threads).split(':', 2)
            user_config.threads min, max
          end

          host = options[:Host]

          if host && (host[0,1] == '.' || host[0,1] == '/')
            user_config.bind "unix://#{host}"
          elsif host && host =~ /^ssl:\/\//
            uri = URI.parse(host)
            uri.port ||= options[:Port] || ::Puma::Configuration::DefaultTCPPort
            user_config.bind uri.to_s
          else
            host ||= ::Puma::Configuration::DefaultTCPHost
            port = options[:Port] || ::Puma::Configuration::DefaultTCPPort

            user_config.port port, host
          end

          user_config.app app
        end
        conf
      end

      def self.run(app, options = {})
        conf   = self.config(app, options)

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
