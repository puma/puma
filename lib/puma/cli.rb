require 'optparse'
require 'puma/configurator'
require 'puma/const'

module Puma
  class CLI
    Options = [
        ['-p', '--port PORT', "Which port to bind to", :@port, 3000],
        ['-a', '--address ADDR', "Address to bind to", :@address, "0.0.0.0"],
        ['-n', '--concurrency INT', "Number of concurrent threads to use",
                                    :@concurrency, 16],
    ]

    Banner = "puma <options> <rackup file>"

    def initialize(argv, stdout=STDOUT)
      @argv = argv
      @stdout = stdout

      setup_options
    end

    def setup_options
      @options = OptionParser.new do |o|
        Options.each do |short, long, help, variable, default|
          instance_variable_set(variable, default)

          o.on(short, long, help) do |arg|
            instance_variable_set(variable, arg)
          end
        end
      end

      @options.banner = Banner

      @options.on_tail "-h", "--help", "Show help" do
        @stdout.puts @options
        exit 1
      end
    end

    def run
      @options.parse! @argv

      @rackup = ARGV.shift || "config.ru"

      unless File.exists?(@rackup)
        raise "Missing rackup file '#{@rackup}'"
      end

      settings = {
        :host => @address,
        :port => @port,
        :concurrency => @concurrency,
        :stdout => @stdout
      }

      config = Puma::Configurator.new(settings) do |c|
        c.listener do |l|
          l.load_rackup @rackup
        end
      end

      config.run
      config.log "Puma #{Puma::Const::PUMA_VERSION} available at #{@address}:#{@port}"
      config.log "Use CTRL-C to stop." 

      config.join
    end
  end
end
