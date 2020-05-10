# frozen_string_literal: true

require "puma/null_io"
require 'puma/debug_logger'
require 'stringio'

module Puma
  # The default implement of an event sink object used by Server
  # for when certain kinds of events occur in the life of the server.
  #
  # The methods available are the events that the Server fires.
  #
  class Events
    class DefaultFormatter
      def call(str)
        str
      end
    end

    class PidFormatter
      def call(str)
        "[#{$$}] #{str}"
      end
    end

    # Create an Events object that prints to +stdout+ and +stderr+.
    #
    def initialize(stdout, stderr)
      @formatter = DefaultFormatter.new
      @stdout = stdout
      @stderr = stderr

      @stdout.sync = true
      @stderr.sync = true

      @debug = ENV.key? 'PUMA_DEBUG'
      @debug_logger = DebugLogger.new(@stderr)

      @hooks = Hash.new { |h,k| h[k] = [] }
    end

    attr_reader :stdout, :stderr
    attr_accessor :formatter

    # Fire callbacks for the named hook
    #
    def fire(hook, *args)
      @hooks[hook].each { |t| t.call(*args) }
    end

    # Register a callback for a given hook
    #
    def register(hook, obj=nil, &blk)
      if obj and blk
        raise "Specify either an object or a block, not both"
      end

      h = obj || blk

      @hooks[hook] << h

      h
    end

    # Write +str+ to +@stdout+
    #
    def log(str)
      @stdout.puts format(str)
    end

    def write(str)
      @stdout.write format(str)
    end

    def debug(str)
      log("% #{str}") if @debug
    end

    # Write +str+ to +@stderr+
    #
    def error(str)
      @debug_logger.error_dump(text: format("ERROR: #{str}"))
      exit 1
    end

    def format(str)
      formatter.call(str)
    end

    # An HTTP connection error has occurred.
    # +error+ a connection exception, +env+ the request
    #
    def connection_error(error, env, text="HTTP connection error")
      @debug_logger.error_dump(error: error, env: env, text: text)
    end

    # An HTTP parse error has occurred.
    # +env+ the request, and +error+ a
    # parsing exception.
    #
    def parse_error(error, env)
      @debug_logger.error_dump(error: error, env: env, text: 'HTTP parse error, malformed request', force: true)
    end

    # An SSL error has occurred.
    # +peeraddr+ peer address, +peercert+
    # any peer certificate (if present), and +error+ an exception object.
    #
    def ssl_error(error, peeraddr, peercert)
      subject = peercert ? peercert.subject : nil
      @debug_logger.error_dump(error: error, text: "SSL error, peer: #{peeraddr}, peer cert: #{subject}", force: true)
    end

    # An unknown error has occurred.
    # +error+ an exception object,
    # +kind+ some additional info, and +env+ the request.
    #
    def unknown_error(error, env=nil, kind="Unknown")
      @debug_logger.error_dump(error: error, env: env, text: kind, force: true)
    end

    def on_booted(&block)
      register(:on_booted, &block)
    end

    def fire_on_booted!
      fire(:on_booted)
    end

    DEFAULT = new(STDOUT, STDERR)

    # Returns an Events object which writes its status to 2 StringIO
    # objects.
    #
    def self.strings
      Events.new StringIO.new, StringIO.new
    end

    def self.stdio
      Events.new $stdout, $stderr
    end

    def self.null
      n = NullIO.new
      Events.new n, n
    end
  end
end
