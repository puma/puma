require 'optparse'
require 'uri'

require 'puma/server'
require 'puma/const'
require 'puma/configuration'
require 'puma/binder'
require 'puma/detect'
require 'puma/daemon_ext'
require 'puma/util'
require 'puma/single'
require 'puma/cluster'

require 'puma/commonlogger'
require 'puma/launcher'

module Puma
  class << self
    # The CLI exports its Puma::Configuration object here to allow
    # apps to pick it up. An app needs to use it conditionally though
    # since it is not set if the app is launched via another
    # mechanism than the CLI class.
    attr_accessor :cli_config
  end

  # Handles invoke a Puma::Server in a command line style.
  #
  class CLI
    KEYS_NOT_TO_PERSIST_IN_STATE = [
      :logger, :lowlevel_error_handler,
      :before_worker_shutdown, :before_worker_boot, :before_worker_fork,
      :after_worker_boot, :before_fork, :on_restart
    ]

    # Create a new CLI object using +argv+ as the command line
    # arguments.
    #
    # +stdout+ and +stderr+ can be set to IO-like objects which
    # this object will report status on.
    #
    def initialize(argv, events=Events.stdio)
      @debug = false
      @argv = argv

      @events = events

      @status = nil

      setup_options

      begin
        @parser.parse! @argv
        @cli_options[:rackup] = @argv.shift if @argv.last
      rescue UnsupportedOption
        exit 1
      end

      @launcher = Puma::Launcher.new(@cli_options, events: @events, argv: @argv)
    end

    ## BACKWARDS COMPAT FOR TESTS

    def error(str)
      @launcher.error(str)
    end

    def debug(str)
      @launcher.debug(str)
    end

    def delete_pidfile
      @launcher.delete_pidfile
    end

    def log(string)
      @launcher.log(string)
    end

    def stop
      @launcher.stop
    end

    def restart
      @launcher.restart
    end

    def write_state
      @launcher.write_state
    end

    def write_pid
      @launcher.write_pid
    end

  private
    def parse_options
      @launcher.send(:parse_options)
    end

    def set_rack_environment
      @launcher.send(:set_rack_environment)
    end
  public

    ## BACKWARDS COMPAT FOR TESTS

    # The Binder object containing the sockets bound to.
    def binder
      @launcher.binder
    end

    # The Configuration object used.
    def config
      @launcher.config
    end

    # The Hash of options used to configure puma.
    def options
      @launcher.options
    end

    # The Events object used to output information.
    attr_reader :events


    def clustered?
      @launcher.clustered?
    end

    def jruby?
      Puma.jruby?
    end

    def windows?
      Puma.windows?
    end

    def env
      @launcher.env
    end

    def jruby_daemon_start
      @launcher.jruby_daemon_start
    end

    def restart!
      @launcher.restart!
    end

    # Parse the options, load the rackup, start the server and wait
    # for it to finish.
    #
    def run
      @launcher.run
    end

    def reload_worker_directory
      @launcher.reload_worker_directory
    end

    def phased_restart
      @launcher.phased_restart
    end

    def redirect_io
      @launcher.redirect_io
    end

    def stats
      @launcher.stats
    end

    def halt
      @launcher.halt
    end

  private
    def unsupported(str)
      @events.error(str)
      raise UnsupportedOption
    end

    # Build the OptionParser object to handle the available options.
    #

    def setup_options
      @cli_options = {}

      @parser = OptionParser.new do |o|
        o.on "-b", "--bind URI", "URI to bind to (tcp://, unix://, ssl://)" do |arg|
          (@cli_options[:binds] ||= []) << arg
        end

        o.on "-C", "--config PATH", "Load PATH as a config file" do |arg|
          @cli_options[:config_file] = arg
        end

        o.on "--control URL", "The bind url to use for the control server",
                              "Use 'auto' to use temp unix server" do |arg|
          if arg
            @cli_options[:control_url] = arg
          elsif jruby?
            unsupported "No default url available on JRuby"
          end
        end

        o.on "--control-token TOKEN",
             "The token to use as authentication for the control server" do |arg|
          @cli_options[:control_auth_token] = arg
        end

        o.on "-d", "--daemon", "Daemonize the server into the background" do
          @cli_options[:daemon] = true
          @cli_options[:quiet] = true
        end

        o.on "--debug", "Log lowlevel debugging information" do
          @cli_options[:debug] = true
        end

        o.on "--dir DIR", "Change to DIR before starting" do |d|
          @cli_options[:directory] = d.to_s
          @cli_options[:worker_directory] = d.to_s
        end

        o.on "-e", "--environment ENVIRONMENT",
             "The environment to run the Rack app on (default development)" do |arg|
          @cli_options[:environment] = arg
        end

        o.on "-I", "--include PATH", "Specify $LOAD_PATH directories" do |arg|
          $LOAD_PATH.unshift(*arg.split(':'))
        end

        o.on "-p", "--port PORT", "Define the TCP port to bind to",
                                  "Use -b for more advanced options" do |arg|
          binds = (@cli_options[:binds] ||= [])
          binds << "tcp://#{Configuration::DefaultTCPHost}:#{arg}"
        end

        o.on "--pidfile PATH", "Use PATH as a pidfile" do |arg|
          @cli_options[:pidfile] = arg
        end

        o.on "--preload", "Preload the app. Cluster mode only" do
          @cli_options[:preload_app] = true
        end

        o.on "--prune-bundler", "Prune out the bundler env if possible" do
          @cli_options[:prune_bundler] = true
        end

        o.on "-q", "--quiet", "Quiet down the output" do
          @cli_options[:quiet] = true
        end

        o.on "-R", "--restart-cmd CMD",
             "The puma command to run during a hot restart",
             "Default: inferred" do |cmd|
          @cli_options[:restart_cmd] = cmd
        end

        o.on "-S", "--state PATH", "Where to store the state details" do |arg|
          @cli_options[:state] = arg
        end

        o.on '-t', '--threads INT', "min:max threads to use (default 0:16)" do |arg|
          min, max = arg.split(":")
          if max
            @cli_options[:min_threads] = min
            @cli_options[:max_threads] = max
          else
            @cli_options[:min_threads] = 0
            @cli_options[:max_threads] = arg
          end
        end

        o.on "--tcp-mode", "Run the app in raw TCP mode instead of HTTP mode" do
          @cli_options[:mode] = :tcp
        end

        o.on "-V", "--version", "Print the version information" do
          puts "puma version #{Puma::Const::VERSION}"
          exit 0
        end

        o.on "-w", "--workers COUNT",
                   "Activate cluster mode: How many worker processes to create" do |arg|
          @cli_options[:workers] = arg.to_i
        end

        o.on "--tag NAME", "Additional text to display in process listing" do |arg|
          @cli_options[:tag] = arg
        end

        o.on "--redirect-stdout FILE", "Redirect STDOUT to a specific file" do |arg|
          @cli_options[:redirect_stdout] = arg
        end

        o.on "--redirect-stderr FILE", "Redirect STDERR to a specific file" do |arg|
          @cli_options[:redirect_stderr] = arg
        end

        o.on "--[no-]redirect-append", "Append to redirected files" do |val|
          @cli_options[:redirect_append] = val
        end

        o.banner = "puma <options> <rackup file>"

        o.on_tail "-h", "--help", "Show help" do
          log o
          exit 0
        end
      end
    end
  end
end
