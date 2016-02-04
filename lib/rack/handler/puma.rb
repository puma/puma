require 'rack/handler'
require 'puma'

module Rack
  module Handler
    module Puma
      DEFAULT_OPTIONS = {
        :Host    => '0.0.0.0',
        :Port    => 8080,
        :Threads => '0:16',
        :Verbose => false,
        :Silent => false
      }

      def self.run(app, options = {})
        options  = DEFAULT_OPTIONS.merge(options)

        if options.delete(:Verbose)
          app = Rack::CommonLogger.new(app, STDOUT)
        end

        if options[:environment]
          ENV['RACK_ENV'] = options[:environment].to_s
        end

        options[:binds] ||= []
        options[:binds] << "tcp://#{ options.delete(:Host) }:#{ options.delete(:Port) }"
        options[:min_threads], options[:max_threads] = options.delete(:Threads).split(':', 2)
        options[:app] = app
        events        = options.delete(:Silent) ? ::Puma::Events.strings : ::Puma::Events.stdio

        launcher = ::Puma::Launcher.new(options, events: events)

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

