require 'optparse'
require 'puma/const'
require 'puma/configuration'
require 'yaml'
module Puma
  class ControlCLI

    def initialize(argv)
      @options = {}
      OptionParser.new do |option|
        option.banner = "Usage: pumactl (options) (status|stop|restart)"
        option.on "-S", "--state PATH", "Where the state file to use is" do |arg|
          @options[:status_path] = arg
        end
        option.on "-Q", "--quiet", "Not display messages" do |arg|
          @options[:quiet_flag] = true
        end
        option.on_tail("-H", "--help", "Show this message") do
          puts option
          exit
        end
        option.on_tail("-V", "--version", "Show version") do
          puts Const::PUMA_VERSION
          exit
        end
      end.parse!(argv)
      command = argv.shift
      @options[:command] = command if command
    end
    
    def puma_started?
      begin
        Process.getpgid( @configuretion["pid"] )
        true
      rescue Errno::ESRCH
        false
      end
    end

    def message msg
      unless @options[:quiet_flag]
        puts msg
      end
    end

    def signal s
      Process.kill(s, @configuretion["pid"])
      message "Signal #{s}" 
    end

    def run
      if @options.has_key? :command
        raise "Status path not set, use -S option" unless @options.has_key? :status_path
        raise "File not found: #{@options[:status_path]} " unless File.exist? @options[:status_path]
        @configuretion = YAML.load File.read(@options[:status_path])
        
        if puma_started?
          case @options[:command]
          when "status" then
            message "Puma is started" 
          when "stop" then
            signal "SIGTERM"
          when "restart" then
            signal "SIGUSR2"
          else
            message "Use -H for help"
          end
        else
          message "Puma not started" 
          exit 1
        end
      else
        message "Use -H for help"
      end
    end
  end
end  
