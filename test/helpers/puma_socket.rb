# frozen_string_literal: true

module PumaTest

  # Note: no setup or teardown, make sure to initialize @ios = []
  #
  module PumaSocket
    HOST = '127.0.0.1'
    RESP_READ_LEN = 65_536
    RESP_READ_TIMEOUT = 10
    RESP_SPLIT = "\r\n\r\n"
    NO_ENTITY_BODY = Puma::STATUS_WITH_NO_ENTITY_BODY

    def before_setup
      @ios_to_close ||= []
      @tcp_port = nil
      @bind_path = nil
      @port = nil
      super
    end

    def after_teardown
      return if skipped?
      # Errno::EBADF raised on macOS
      @ios_to_close.each do |io|
        begin
          io.close if io.respond_to?(:close) && !io.closed?
          File.unlink io.path if io.is_a? File
        rescue Errno::EBADF
        ensure
          io = nil
        end
      end
      super
    end

    def header(skt)
      headers = []
      while true
        skt.wait_readable 1
        line = skt.gets
        break if line == "\r\n"
        headers << line.strip
      end

      headers
    end

    def send_http_read_resp_body(req, port: nil, path: nil, len: nil)
      skt = send_http req, port: port, path: path
      skt.read_body len: len
    end

    def send_http_read_response(req, port: nil, path: nil, len: nil)
      skt = send_http req, port: port, path: path
      skt.read_response len: len
    end

    def send_http(req, port: nil, path: nil)
      skt = new_connection port: port, path: path
      skt.syswrite req
      skt
    end

    READ_BODY = -> (timeout = nil, len: nil) {
      self.read_response(timeout, len: len).split(RESP_SPLIT, 2).last
    }

    READ_RESPONSE = -> (timeout = nil, len: nil) do
      timeout ||= RESP_READ_TIMEOUT
      content_length = nil
      chunked = nil
      status = nil
      no_body = nil
      response = +''
      t_st = Process.clock_gettime Process::CLOCK_MONOTONIC
      read_len = len || RESP_READ_LEN
      if self.to_io.wait_readable timeout
        loop do
          begin
            part = self.read_nonblock(read_len, exception: false)
            case part
            when String
              status ||= part[/\AHTTP\/1\.[01] (\d{3})/, 1]
              if status
                no_body ||= NO_ENTITY_BODY.key? status.to_i || status.to_i < 200
              end
              if no_body && part.end_with?(RESP_SPLIT)
                return response << part
              end

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
                    body.bytesize == content_length
                  elsif chunked
                    body.end_with? "0\r\n\r\n"
                  elsif !hdrs.empty? && !body.empty?
                    true
                  else
                    false
                  end
                if ret
                  return response
                end
              end
              sleep 0.000_1
            when :wait_readable, :wait_writable # :wait_writable for ssl
              sleep 0.000_2
            when nil
              if response.empty?
                raise EOFError
              else
                return response
              end
            end
            if timeout < Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st
              raise Timeout::Error, 'Client Read Timeout'
            end
          end
        end
      else
        raise Timeout::Error, 'Client Read Timeout'
      end
    end

    REQ_WRITE = -> (str) { self.syswrite str }

    def new_connection(port: nil, path: nil)
      port  ||= @port || @tcp_port
      path  ||= @bind_path
      @host ||= HOST
      skt = if path && !port
        UNIXSocket.new path.sub(/\A@/, "\0")
      elsif port && !path
        TCPSocket.new @host, port
      else
        raise 'port or path must be set!'
      end
      skt.define_singleton_method :read_response, READ_RESPONSE
      skt.define_singleton_method :read_body, READ_BODY
      skt.define_singleton_method :<<, REQ_WRITE
      @ios_to_close << skt
      skt
    end

    private
    def no_body(status)

    end
  end
end
