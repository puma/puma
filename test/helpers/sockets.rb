require 'socket'

module TestPuma

  # @!macro [new] req
  #   @param [String] path request uri path
  #   @param [Float] dly: delay in app when using 'ci' rackups
  #   @param [Integer, String] body_conf: response body type and size in kB when using 'ci' rackups

  # @!macro [new] tout
  #   @param [Float] timeout: read timeout for socket

  # @!macro [new] ret_skt
  #   @return [SktSSL, SktTCP, SktUNIX] the opened socket


  RESP_READ_TIMEOUT = 10

  module SktPrepend

    RESP_READ_LEN = 1_024 * 64
    RESP_SPLIT = "\r\n\r\n"

    WRITE_TIMEOUT = 5

    # Writes a string to the socket using `syswrite`.
    # @param [String] str
    # @return [Integer] number of bytes written
    def write(str)
      fast_write str
    end

    # Writes a string to the socket using `syswrite`.
    # @param [String] str
    # @return [self]
    def <<(str)
      fast_write str
      self
    end

    # Writes a string to the socket using `syswrite`.
    # @param [String] str the string to write
    # @return [Integer] the number of bytes written
    def fast_write(str)
      return unless str.is_a? String
      n = 0
      byte_size = str.bytesize
      while n < byte_size
        begin
          n += syswrite(n.zero? ? str : str.byteslice(n..-1))
        rescue Errno::EAGAIN, Errno::EWOULDBLOCK => e
          unless wait_writable WRITE_TIMEOUT
            raise e
          end
          retry
        rescue => e
          raise e
        end
      end
    end

    # Returns the response body
    # @!macro tout
    # @return [String] response body
    def read_body(timeout = nil)
      read_response(timeout).last
    end

    # Reads the response as a two element array
    # @note Cannot be used with responses without bodies, like 'HEAD' requests
    # @!macro tout
    # @return [Array<String, String>] array is [header string, body]
    def read_response(timeout = nil)
      timeout ||= RESP_READ_TIMEOUT
      content_length = nil
      chunked = nil
      response = +''
      timeout_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while to_io.wait_readable timeout
        timeout = timeout_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        begin
          # part = sysread RESP_READ_LEN
          part = read_nonblock(RESP_READ_LEN, exception: false)
          case part
          when String
            unless content_length || chunked
              chunked ||= part.include? "\r\nTransfer-Encoding: chunked\r\n"
              content_length = (t = part[/^Content-Length: (\d+)/i , 1]) ? t.to_i : nil
            end

            response << part
            hdrs, body = response.split RESP_SPLIT, 2
            unless body.nil?
              # below could be simplified, but allows for debugging...
              ret =
                if content_length
                  # STDOUT.puts "body.bytesize #{body.bytesize} content length #{content_length}"
                  body.bytesize == content_length
                elsif chunked
                  # STDOUT.puts "#{body.bytesize} chunked"
                  body.end_with? "\r\n0\r\n\r\n"
                elsif !hdrs.empty? && !body.empty?
                  true
                else
                  false
                end
              if ret
                @connection_close = hdrs.include? "\nConnection: close"
                return [hdrs, body]
              end
            end
            sleep 0.000_1
          when :wait_readable, :wait_writable # :wait_writable for ssl
            sleep 0.000_2
          when nil
            @connection_close = true
            raise EOFError
          end
        end
      end
      raise Timeout::Error, 'Client Read Timeout'
    end

    # Reads the raw response as string
    # @!macro tout
    # @return <String>
    def read_raw(timeout = nil)
      timeout ||= RESP_READ_TIMEOUT
      response = +''
      timeout_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
      while to_io.wait_readable timeout
        timeout = timeout_end - Process.clock_gettime(Process::CLOCK_MONOTONIC)

        part = read_nonblock(RESP_READ_LEN, exception: false)
        case part
        when String
          response << part
          sleep 0.000_1
        when :wait_readable, :wait_writable # :wait_writable for ssl
          sleep 0.000_2
        when nil
          return response
        end
      end
      raise Timeout::Error, 'Client Read Timeout'
    end
  end

  unless Object.const_defined?(:Puma) && ::Puma.const_defined?(:HAS_SSL) && !Puma::HAS_SSL
    require 'openssl'
    # The SSLSocket class used by the TestPuma framework.  The `SktPrepend` module
    # is prepended.  The socket is opened with parameters set by `bind_type`.
    class SktSSL < ::OpenSSL::SSL::SSLSocket
      prepend SktPrepend
    end
  end

  # The TCPSocket class used by the TestPuma framework.  The `SktPrepend` module
  # is prepended.  The socket is opened with parameters set by `bind_type`.
  class SktTCP < ::TCPSocket
    prepend SktPrepend
  end

  if Object.const_defined? :UNIXSocket
    # The UNIXSocket class used by the TestPuma framework.  The `SktPrepend` module
    # is prepended.  The socket is opened with parameters set by `bind_type`.
    class SktUNIX < ::UNIXSocket
      prepend SktPrepend
    end
  end
end
