# frozen_string_literal: true

require 'puma/null_io'
require 'puma/error_logger'
require 'stringio'

module Puma

  # Handles logging concerns for both standard messages
  # (+stdout+) and errors (+stderr+).
  class LogWriter

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

    attr_reader :stdout,
                :stderr

    attr_accessor :formatter, :custom_logger

    # Create a LogWriter that prints to +stdout+ and +stderr+.
    def initialize(stdout, stderr)
      @formatter = DefaultFormatter.new
      @stdout = stdout
      @stderr = stderr

      @debug = ENV.key?('PUMA_DEBUG')
      @error_logger = ErrorLogger.new(@stderr)
    end

    DEFAULT = new(STDOUT, STDERR)

    # Returns an LogWriter object which writes its status to
    # two StringIO objects.
    def self.strings
      LogWriter.new(StringIO.new, StringIO.new)
    end

    def self.stdio
      LogWriter.new($stdout, $stderr)
    end

    def self.null
      n = NullIO.new
      LogWriter.new(n, n)
    end

    # Write +str+ to +@stdout+
    def log(str)
      if @custom_logger
        @custom_logger.write(format(str))
      else
        @stdout.puts(format(str)) if @stdout.respond_to? :puts
        @stdout.flush unless @stdout.sync
      end
    rescue Errno::EPIPE
    end

    def write(str)
      @stdout.write(format(str))
    end

    def debug(str)
      log("% #{str}") if @debug
    end

    # Write +str+ to +@stderr+
    def error(str)
      @error_logger.info(text: format("ERROR: #{str}"))
      exit 1
    end

    def format(str)
      formatter.call(str)
    end

    # An HTTP connection error has occurred.
    # +error+ a connection exception, +req+ the request,
    # and +text+ additional info
    # @version 5.0.0
    def connection_error(error, req, text="HTTP connection error")
      @error_logger.info(error: error, req: req, text: text)
    end

    # An HTTP parse error has occurred.
    # +error+ a parsing exception,
    # and +req+ the request.
    def parse_error(error, req)
      @error_logger.info(error: error, req: req, text: 'HTTP parse error, malformed request')
    end

    # An SSL error has occurred.
    # @param error <Puma::MiniSSL::SSLError>
    # @param ssl_socket <Puma::MiniSSL::Socket>
    def ssl_error(error, ssl_socket)
      peeraddr = ssl_socket.peeraddr.last rescue "<unknown>"
      peercert = ssl_socket.peercert
      subject = peercert ? peercert.subject : nil
      @error_logger.info(error: error, text: "SSL error, peer: #{peeraddr}, peer cert: #{subject}")
    end

    # An unknown error has occurred.
    # +error+ an exception object, +req+ the request,
    # and +text+ additional info
    def unknown_error(error, req=nil, text="Unknown error")
      @error_logger.info(error: error, req: req, text: text)
    end

    # Log occurred error debug dump.
    # +error+ an exception object, +req+ the request,
    # and +text+ additional info
    # @version 5.0.0
    def debug_error(error, req=nil, text="")
      @error_logger.debug(error: error, req: req, text: text)
    end
  end
end
