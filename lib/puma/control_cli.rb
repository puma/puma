require 'optparse'
require 'puma/const'
require 'puma/configuration'
require 'yaml'
require 'uri'
require 'socket'
module Puma
  class ControlCLI

    COMMANDS = %w{status restart stop halt}

    def is_windows?
      RUBY_PLATFORM =~ /(win|w)32$/ ? true : false
    end

    def initialize(argv, stdout=STDOUT)
      
      @stdout = stdout
      @options = {}
      
      OptionParser.new do |option|
        option.banner = "Usage: pumactl (-S status_file | -C url -T token) (#{COMMANDS.join("|")})"
        option.on "-S", "--state PATH", "Where the state file to use is" do |arg|
          @options[:status_path] = arg
        end
        option.on "-Q", "--quiet", "Not display messages" do |arg|
          @options[:quiet_flag] = true
        end
        option.on "-P", "--pidfile PATH", "Pid file" do |arg|
          @options[:pid_file] = arg
        end
        option.on "-C", "--control-url URL", "The bind url to use for the control server" do |arg|
          @options[:control_url] = arg
        end
        option.on "-T", "--control-token TOKEN", "The token to use as authentication for the control server" do |arg|
          @options[:control_auth_token] = arg
        end
        option.on_tail("-H", "--help", "Show this message") do
          @stdout.puts option
          exit
        end
        option.on_tail("-V", "--version", "Show version") do
          puts Const::PUMA_VERSION
          exit
        end
      end.parse!(argv)
      
      command = argv.shift
      @options[:command] = command if command
      
      # check present of command
      unless @options[:command]
        raise "Available commands: #{COMMANDS.join(", ")}"
      end      
      unless COMMANDS.include? @options[:command]
        raise "Invalid command: #{@options[:command]}" 
      end
      
    rescue => e
      @stdout.puts e.message
      exit 1
    end
    
    def message msg
      @stdout.puts msg unless @options[:quiet_flag]
    end

    def prepare_configuration
      if @options.has_key? :status_path
        raise "Status file not found: #{@options[:status_path]} " unless File.exist? @options[:status_path]
        status = YAML.load File.read(@options[:status_path])
        if status.has_key? "config"
          # get control_url
          if status["config"].options.has_key?(:control_url)
            @options[:control_url] = status["config"].options[:control_url]
          end
          # get control_auth_token
          if status["config"].options.has_key?(:control_auth_token)
            @options[:control_auth_token] = status["config"].options[:control_auth_token]
          end
          # get pid
          @options[:pid] = status["pid"].to_i
        else
          raise "Invalid status file: #{@options[:status_path]}"
        end
      elsif @options.has_key? :pid_file
        # get pid from pid_file
        @options[:pid] = File.open(@options[:pid_file]).gets.to_i
      end
      
    end

    def send_request
      uri = URI.parse @options[:control_url]
      
      # create server object by scheme
      @server = case uri.scheme
      when "tcp"
        TCPSocket.new uri.host, uri.port
      when "unix"
        UNIXSocket.new "#{uri.host}#{uri.path}"
      else
        raise "Invalid scheme: #{uri.scheme}"
      end
      
      unless @options[:command] == "status"
        url = "/#{@options[:command]}"
        if @options.has_key?(:control_auth_token)
          url = url + "?token=#{@options[:control_auth_token]}"
        end
        @server << "GET #{url} HTTP/1.0\r\n\r\n"
        response = @server.read.split("\r\n")
        (@http,@code,@message) = response.first.split(" ")
        if @code == "403"
          raise "Unauthorized access to server (wrong auth token)"
        elsif @code != "200"
          raise "Bad response from server: #{@code}"
        end
        message "Command #{@options[:command]} sent success"
      else
        message "Puma is started"
      end
      
      @server.close
    end

    def send_signal
      Process.getpgid(@options[:pid])
      case @options[:command]
      when "restart"
        Process.kill("SIGUSR2", @options[:pid])
      when "halt"
        Process.kill("QUIT", @options[:pid])
      when "stop"
        Process.kill("SIGTERM", @options[:pid])
      else
        message "Puma is started"
        return
      end
      message "Command #{@options[:command]} sent success"
    end

    def run
      prepare_configuration
    
      if is_windows?
        send_request
      else
        @options.has_key?(:control_url) ? send_request : send_signal
      end

    rescue => e
      message e.message
      exit 1
    end
  end
end  
