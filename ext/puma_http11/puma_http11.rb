# frozen_string_literal: true

require "protocol/http1/connection"

module Puma
  RUBY_PARSER = true

  class HttpParserError < IOError
  end

  class HttpParser

    attr_reader :body

    RETURN_NEWLINE = /\r\n/
    SCHEME = %r{\Ahttps?://}

    def initialize
      reset
    end

    def execute(req, data, start)
      # Don't start parsing until the request line and all of the headers have been read
      unless @finished
        return 0 unless RETURN_NEWLINE.match?(data)
        reset
        @finished = true
      end

      @connection = Protocol::HTTP1::Connection.new(StringIO.new(data))
      host, method, path, version, headers, _body_ = @connection.read_request
      req.merge!(headers.to_h)
      uri = URI(path)
      req["HOST"] = host
      req["REQUEST_METHOD"] = method
      req["REQUEST_URI"] = path.partition("#").first

      unless path.match? SCHEME
        req['REQUEST_PATH'] = uri.path
        req['QUERY_STRING'] = uri.query
        req['FRAGMENT'] = uri.fragment
      end

      req['SERVER_PROTOCOL'] = version

      @body = @connection.stream.read || ""

      nread
    rescue Protocol::HTTP1::BadHeader, Protocol::HTTP1::LineLengthError, EOFError
      raise Puma::HttpParserError
    end

    def nread
      @connection ? @connection.stream.pos : 0
    end

    def reset
      @finished = false
      @error = false
      @connection = nil
      @body = ""
      @connection = nil
    end

    def finished?
      @finished
    end

    def error?
      @error
    end
  end
end
