# frozen_string_literal: true

require 'socket'
require_relative '../test_puma'
require_relative 'response'

module TestPuma

  # @!macro [new] resp
  #   @param timeout: [Float, nil] total socket read timeout, defaults to `RESP_READ_TIMEOUT`
  #   @param len: [ Integer, nil] the `read_nonblock` maxlen, defaults to `RESP_READ_LEN`


  # This module contains the methods included in PumaSSLSocket, PumaTCPSocket,
  # and PumaUNIXSocket, which are subclasses of the native Ruby sockets.
  # All methods add functionality related to their use with client HTTP connections.
  #
  module PumaSocketInclude
    RESP_READ_LEN = 65_536
    RESP_READ_TIMEOUT = 10

    NO_ENTITY_BODY = Puma::STATUS_WITH_NO_ENTITY_BODY

    # Reads all that is available on the socket.  Used for reading sockets that
    # contain multiple responses.
    # @param timeout: [Float, nil] total socket read timeout, defaults to `RESP_READ_TIMEOUT`
    # @return [String]
    #
    def read_all(timeout: RESP_READ_TIMEOUT)
      end_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (timeout || RESP_READ_TIMEOUT)
      read = String.new # rubocop: disable Performance/UnfreezeString
      prev_size = 0
      loop do
        raise(Timeout::Error, 'Client Read Timeout') if Process.clock_gettime(Process::CLOCK_MONOTONIC) > end_time
        if wait_readable 1
          read << sysread(RESP_READ_LEN)
        end
        ttl_read = read.bytesize
        return read if prev_size == ttl_read && !ttl_read.zero?
        prev_size = ttl_read
      end
    rescue EOFError
      return read
    rescue => e
      raise e
    end

    # Reads the response body on the socket.  Assumes one response, use
    # `read_all` to read multiple responses.
    # @!macro resp
    # @return [String] the HTTP body
    #
    def read_body(timeout: nil, len: nil)
      self.read_response(timeout: nil, len: nil).split(RESP_SPLIT, 2).last
    end

    # Reads the HTTP response on the socket.  Assumes one response, use `read_all`
    # to read multiple responses.
    # @!macro resp
    # @return [Response] the HTTP response
    #
    def read_response(timeout: nil, len: nil)
      content_length = nil
      chunked = nil
      status = nil
      no_body = nil
      response = Response.new
      read_len = len || RESP_READ_LEN

      timeout  ||= RESP_READ_TIMEOUT
      time_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      time_end   = time_start + timeout
      times = []
      time_read = nil

      loop do
        begin
          self.to_io.wait_readable timeout
          time_read ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
          part = self.read_nonblock(read_len, exception: false)
          case part
          when String
            times << (Process.clock_gettime(Process::CLOCK_MONOTONIC) - time_read).round(4)
            status ||= part[/\AHTTP\/1\.[01] (\d{3})/, 1]
            if status
              no_body ||= NO_ENTITY_BODY.key? status.to_i || status.to_i < 200
            end
            if no_body && part.end_with?(RESP_SPLIT)
              response.times = times
              return response << part
            end

            unless content_length || chunked
              chunked ||= part.downcase.include? "\r\ntransfer-encoding: chunked\r\n"
              content_length = (t = part[/^Content-Length: (\d+)/i , 1]) ? t.to_i : nil
            end
            response << part
            hdrs, body = response.split RESP_SPLIT, 2
            unless body.nil?
              # below could be simplified, but allows for debugging...
              finished =
                if content_length
                  body.bytesize == content_length
                elsif chunked
                  body.end_with? "0\r\n\r\n"
                elsif !hdrs.empty? && !body.empty?
                  true
                else
                  false
                end
              response.times = times
              return response if finished
            end
            sleep 0.000_1
          when :wait_readable
            # continue loop
          when :wait_writable # :wait_writable for ssl
            to = time_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)
            self.to_io.wait_writable to
          when nil
            if response.empty?
              raise EOFError
            else
              response.times = times
              return response
            end
          end
          timeout = time_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)
          if timeout <= 0
            raise Timeout::Error, 'Client Read Timeout'
          end
        end
      end
    end

    # Writes the request/data to the socket.  Returns self
    # @param req [String] the request or data to write
    # @return [self] the socket
    #
    def send_http(req = GET_11)
      if String === req
        req_size = req.bytesize
        req_sent = 0
        req_sent += syswrite req while req_sent < req_size
      end
      self
    end
    alias_method :<<, :send_http

    # Writes the request/data to the socket and returns the response body.
    # Assumes one response, use `read_all` to read multiple responses.
    # @param req [String] the request or data to write
    # @!macro resp
    # @return [String] The response body.  Chunked bodies are not decoded.
    #
    def send_http_read_body(req = GET_11, timeout: nil, len: nil)
      send_http_read_response(req, timeout: timeout, len: len)
        .split(RESP_SPLIT, 2).last
    end

    # Writes the request/data to the socket and returns the response.  Assumes
    # one response, use `read_all` to read multiple responses.
    # @param req [String] the request or data to write
    # @!macro resp
    # @return [Response] the HTTP response
    #
    def send_http_read_response(req = GET_11, timeout: nil, len: nil)
      send_http(req).read_response(timeout: timeout, len: len)
    end

    # Uses a single `sysread` statement to read the socket.  Reads `len` bytes
    # from the socket.  A `wait_readable` call using `timeout:` preceeds it.
    # @param len [Integer] the number of bytes to read
    # @param timeout: [Float, Integer] `wait_readable` timeout
    # @return [String]
    #
    def wait_read(len, timeout: 5)
      Thread.pass
      self.wait_readable timeout
      Thread.pass
      sysread len
    end
  end

  class PumaTCPSocket < ::TCPSocket
    include PumaSocketInclude
  end

  if Object.const_defined?(:UNIXSocket)
    class PumaUNIXSocket < ::UNIXSocket
      include PumaSocketInclude
    end
  end

  if ::Puma::HAS_SSL
    class PumaSSLSocket < ::OpenSSL::SSL::SSLSocket
      include PumaSocketInclude
    end
  end
end
