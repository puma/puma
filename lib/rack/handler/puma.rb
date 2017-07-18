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

        default_options = DEFAULT_OPTIONS.dup

        # Libraries pass in values such as :Port and there is no way to determine
        # if it is a default provided by the library or a special value provided
        # by the user. A special key `user_supplied_options` can be passed. This
        # contains an array of all explicitly defined user options. We then
        # know that all other values are defaults
        if user_supplied_options = options.delete(:user_supplied_options)
          (options.keys - user_supplied_options).each do |k, v|
            default_options[k] = options.delete(k)
          end
        end

        self.set_host_port_to_config(default_options[:Host], default_options[:Port], default_options)

        conf = ::Puma::Configuration.new(options, default_options) do |user_config, file_config, default_config|
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

          if options[:Host] || options[:Port]
            host = options[:Host] || default_options[:Host]
            port = options[:Port] || default_options[:Port]
            self.set_host_port_to_config(host, port, user_config)
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

      def self.set_host_port_to_config(host, port, config)
        if host && (host[0,1] == '.' || host[0,1] == '/')
          apply_bind_to_config "unix://#{host}", config
        elsif host && host =~ /^ssl:\/\//
          uri = URI.parse(host)
          uri.port ||= port || ::Puma::Configuration::DefaultTCPPort
          apply_bind_to_config uri.to_s, config
        else

          if host
            port ||= ::Puma::Configuration::DefaultTCPPort
          end

          if port
            host ||= ::Puma::Configuration::DefaultTCPHost
            apply_bind_to_config "tcp://#{host}:#{port}", config
          end
        end
      end

      def self.apply_bind_to_config(val, config)
        if config.is_a? ::Puma::DSL
          config.public_send :bind, val
        else
          # Respect any existing :binds value that might already exist
          config[:binds] ||= []
          config[:binds]  << val
        end
      end
    end

    register :puma, Puma
  end
end
