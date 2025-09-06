# frozen_string_literal: true

require "strscan"
require_relative "../../lib/puma/const"
require_relative "../../lib/puma/client"

module Puma
  RUBY_PARSER = true

  class HttpParserError < IOError
  end

  # Hand written HTTP 1.1 parser written in Ruby. Similar to the Ragel approach this parser uses a
  # state machine. However, while Ragel state machine works one character at a time, this parser
  # works in chunks: http_method, target, version, headers, and body.
  #
  # Given this request:
  #
  #  POST /example-page HTTP/1.1
  #  Host: www.example.com
  #  User-Agent: Mozilla/5.0
  #
  #  Hello World
  #
  # Each step of the parser does the following:
  #
  # http_method: "POST"
  # target: "/example-page"
  # version: "HTTP/1.1"
  # headers: "Host: www.example.com", "User-Agent: Mozilla/5.0", "\r\n"
  # body: "Hello World"
  class HttpParser
    include Puma::Const

    STEPS = [
      :http_method,
      :target,
      :version,
      :headers,
      :body
    ]

    # Step delimeters
    SPACE = /\s/
    RETURN_OR_NEWLINE = /[\r\n]/

    SSL = "Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?"

    METHODS = %r{#{SUPPORTED_HTTP_METHODS.join("|")}\b}
    WS = /\s+/
    def http_method(req)
      req["REQUEST_METHOD"] = (@scanner.scan(METHODS) || raise_error!("Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?")).strip
      @scanner.skip(WS)
      @step += 1
    end

    # URL components
    URI = /[^\s#]+/ # Match everything up until whitespace or a hash
    SCHEME = %r{\Ahttps?://}
    PARTS = /\A(?<path>[^?#]*)(\?(?<params>[^#]*))?/
    NWS = /\S*/ # not white space
    FRAGMENT_DELIMETER = /#/
    UNPRINTABLE_CHARACTERS = %r{[^ -~]} # find a character that's not between " " (space) and "~" (tilde)
    def target(req)
      uri = @scanner.scan(URI)
      req["REQUEST_URI"] = uri
      raise_error!("HTTP element REQUEST_URI is longer than the (1024 * 12) allowed length (was #{uri.length})") if uri.length > 1024 * 12
      unless uri.match? SCHEME
        parts = PARTS
          .match(uri)
          .named_captures
        path = parts["path"]
        if path.match? UNPRINTABLE_CHARACTERS
          raise_error!(SSL)
        else
          req["REQUEST_PATH"] = path
          raise_error!("HTTP element REQUEST_PATH is longer than the (8192) allowed length (was #{path.length})") if path.length > 8192
        end
        params = parts["params"] || ""
        if params.match? UNPRINTABLE_CHARACTERS
          raise_error!(SSL)
        else
          req["QUERY_STRING"] = params
          raise_error!("HTTP element QUERY_STRING is longer than the (1024 * 10) allowed length (was #{params.length})") if params.length > 1024 * 10
        end
        if @scanner.skip(FRAGMENT_DELIMETER)
          req["FRAGMENT"] = @scanner.scan(NWS)
          raise_error!("HTTP element FRAGMENT is longer than the 1024 allowed length (was #{req["FRAGMENT"].length})") if req["FRAGMENT"].length > 1024
        end
      end
      @scanner.scan(WS)
      @step += 1
    end

    HTTP_VERSION = %r{(HTTP/1\.[01])}
    RETURN_NEWLINE = %r{\r\n}
    NEWLINE = %r{\n}
    def version(req)
      req["SERVER_PROTOCOL"] = @scanner.scan(HTTP_VERSION) || raise_error!(SSL)
      @scanner.skip(RETURN_NEWLINE) || raise_error!
      @delimeter = RETURN_OR_NEWLINE
      @step += 1
    end

    HEADER = %r{[^\r\n]+\r\n}
    HEADER_FORMAT = /\A([^:]+):\s*([^\r\n]+)/
    DIGITS = /\A\d+\z/
    TRAILING_WS = /\s*$/
    def headers(req)
      while header = @scanner.scan(HEADER)
        @headers_count += 1
        raise_error! if @headers_count > 1024 # TODO Use a  better number
        @headers_total_length += header.length
        raise_error!("HTTP element HEADER is longer than the (1024 * (80 + 32)) allowed length (was 114930)") if @headers_total_length > 1024 * (80 + 32) # TODO Need to figure out how to calculate 114930 better.
        raise_error! unless HEADER_FORMAT.match(header)
        key = $1
        value = $2
        raise_error!("HTTP element FIELD_NAME is longer than the 256 allowed length (was #{key.length})") if key.length > 256
        raise_error!("HTTP element FIELD_VALUE is longer than the 80 * 1024 allowed length (was #{value.length})") if value.length > 80 * 1024
        raise_error! if value.match?(NEWLINE)
        key = key.upcase.tr("_-", ",_")
        key = "HTTP_#{key}" unless ["CONTENT_LENGTH", "CONTENT_TYPE"].include?(key)
        value = value.rstrip
        if req.has_key?(key)
          req[key] << ", #{value}"
        else
          req[key] = value
        end
      end
      if @scanner.skip(RETURN_NEWLINE)
        @step += 1
        @finished = true
      end
      raise_error!(SSL) if @scanner.exist?(/[^\r]\n/) # catch bad headers that are missing a return.
      raise_error!(SSL) if @scanner.exist?(/\r[^\n]/) # catch bad headers that are missing a newline.
    end

    def execute(req, data, start)
      unless @scanner
        reset
        @scanner = StringScanner.new(data)
      end

      send(STEPS[@step], req) while !@finished && @scanner.exist?(@delimeter)

      if @step == 0
        raise_error!("Invalid HTTP format, parsing fails. Are you trying to open an SSL connection to a non-SSL Puma?")
      end

      nread
    end

    def body
      @body ||= @scanner.rest.tap { @scanner.terminate } # Using terminate feels hacky to me. Is there something better?
    end

    def nread
      @scanner&.pos || 0
    end

    def reset
      @step = 0
      @finished = false
      @delimeter = SPACE
      @error = false
      @scanner = nil
      @body = nil
      @headers_count = 0
      @headers_total_length = 0
    end

    def finished?
      @finished
    end

    def raise_error!(message = nil)
      @error = true
      raise HttpParserError.new(message)
    end

    def error?
      @error
    end
  end
end
