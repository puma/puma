# frozen_string_literal: true

require 'optparse'
require_relative '../../lib/puma/state_file'
require_relative '../../lib/puma/const'
require_relative '../../lib/puma/detect'
require_relative '../../lib/puma/configuration'
require 'uri'
require 'socket'
require 'json'

module TestPuma

  # Similar to puma_ctl.rb, but returns objects.  Command list is minimal.
  #
  class PumaInfo
    # @version 5.0.0
    PRINTABLE_COMMANDS = %w{gc-stats stats stop thread-backtraces}.freeze

    COMMANDS = (PRINTABLE_COMMANDS + %w{gc}).freeze

    attr_reader :master_pid

    def initialize(argv, stdout=STDOUT, stderr=STDERR)
      @state = nil
      @quiet = false
      @pidfile = nil
      @pid = nil
      @control_url = nil
      @control_auth_token = nil
      @config_file = nil
      @command = nil
      @environment = ENV['RACK_ENV'] || ENV['RAILS_ENV']

      @argv = argv
      @stdout = stdout
      @stderr = stderr
      @cli_options = {}

      opts = OptionParser.new do |o|
        o.banner = "Usage: pumactl (-p PID | -P pidfile | -S status_file | -C url -T token | -F config.rb) (#{PRINTABLE_COMMANDS.join("|")})"

        o.on "-S", "--state PATH", "Where the state file to use is" do |arg|
          @state = arg
        end

        o.on "-Q", "--quiet", "Not display messages" do |arg|
          @quiet = true
        end

        o.on "-C", "--control-url URL", "The bind url to use for the control server" do |arg|
          @control_url = arg
        end

        o.on "-T", "--control-token TOKEN", "The token to use as authentication for the control server" do |arg|
          @control_auth_token = arg
        end

        o.on "-F", "--config-file PATH", "Puma config script" do |arg|
          @config_file = arg
        end

        o.on "-e", "--environment ENVIRONMENT",
          "The environment to run the Rack app on (default development)" do |arg|
          @environment = arg
        end

        o.on_tail("-H", "--help", "Show this message") do
          @stdout.puts o
          exit
        end

        o.on_tail("-V", "--version", "Show version") do
          @stdout.puts Const::PUMA_VERSION
          exit
        end
      end

      opts.order!(argv) { |a| opts.terminate a }
      opts.parse!

      unless @config_file == '-'
        environment = @environment || 'development'

        if @config_file.nil?
          @config_file = %W(config/puma/#{environment}.rb config/puma.rb).find do |f|
            File.exist?(f)
          end
        end

        if @config_file
          config = Puma::Configuration.new({ config_files: [@config_file] }, {})
          config.load
          @state              ||= config.options[:state]
          @control_url        ||= config.options[:control_url]
          @control_auth_token ||= config.options[:control_auth_token]
          @pidfile            ||= config.options[:pidfile]
        end
      end

      @master_pid = File.binread(@state)[/^pid: +(\d+)/, 1].to_i

    rescue => e
      @stdout.puts e.message
      exit 1
    end

    def message(msg)
      @stdout.puts msg unless @quiet
    end

    def prepare_configuration
      if @state
        unless File.exist? @state
          raise "State file not found: #{@state}"
        end

        sf = Puma::StateFile.new
        sf.load @state

        @control_url = sf.control_url
        @control_auth_token = sf.control_auth_token
        @pid = sf.pid
      end
    end

    def send_request
      uri = URI.parse @control_url

      # create server object by scheme
      server =
        case uri.scheme
        when 'ssl'
          require 'openssl'
          OpenSSL::SSL::SSLSocket.new(
            TCPSocket.new(uri.host, uri.port),
            OpenSSL::SSL::SSLContext.new)
            .tap { |ssl| ssl.sync_close = true }  # default is false
            .tap(&:connect)
        when 'tcp'
          TCPSocket.new uri.host, uri.port
        when 'unix'
          # check for abstract UNIXSocket
          UNIXSocket.new(@control_url.start_with?('unix://@') ?
            "\0#{uri.host}#{uri.path}" : "#{uri.host}#{uri.path}")
        else
          raise "Invalid scheme: #{uri.scheme}"
        end

      url = "/#{@command}"

      if @control_auth_token
        url = url + "?token=#{@control_auth_token}"
      end

      server.syswrite "GET #{url} HTTP/1.0\r\n\r\n"

      unless data = server.read
        raise 'Server closed connection before responding'
      end

      response = data.split("\r\n")

      if response.empty?
        raise "Server sent empty response"
      end

      @http, @code, @message = response.first.split(' ',3)

      if @code == '403'
        raise 'Unauthorized access to server (wrong auth token)'
      elsif @code == '404'
        raise "Command error: #{response.last}"
      elsif @code == '500' && @command == 'stop-sigterm'
        # expected with stop-sigterm
      elsif @code != '200'
        raise "Bad response from server: #{@code}"
      end
      return unless PRINTABLE_COMMANDS.include? @command
      JSON.parse response.last, {symbolize_names: true}
    ensure
      if server
        if uri.scheme == 'ssl'
          server.sysclose
        else
          server.close unless server.closed?
        end
      end
    end

    def run(cmd)
      return unless COMMANDS.include?(cmd)
      @command = cmd
      prepare_configuration
      send_request
    rescue => e
      message e.message
      exit 1
    end
  end
end
