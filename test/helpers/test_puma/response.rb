# frozen_string_literal: true

module TestPuma

  # A subclass of String, allows processing the response returned by
  # `PumaSocket#send_http_read_response` and the `PumaSocketInclude#read_response`
  # method included in the socket classes (created with `PumaSocket#new_socket`,
  # `PumaSocket#send_http`, and `PumaSocket#send_http_array`).
  #
  class Response < String

    attr_accessor :times

    # Returns response headers as an array of lines
    # @return [Array<String>]
    def headers
      @headers ||= begin
        ary = self.split(RESP_SPLIT, 2).first.split LINE_SPLIT
        @status = ary.shift
        ary
      end
    end

    # Returns response headers as a hash. All keys and values are strings.
    # @return [Hash]
    def headers_hash
      @headers_hash ||= headers.map { |hdr| hdr.split ': ', 2 }.to_h
    end

    def status
      headers unless @status
      @status
    end

    def body
      self.split(RESP_SPLIT, 2).last
    end

    # Decodes a chunked body
    # @return [String] the decoded body
    def decode_body
      decoded = String.new  # rubocop: disable Performance/UnfreezeString

      body = self.split(RESP_SPLIT, 2).last
      body = body.byteslice 0, body.bytesize - 5 # remove terminating bytes

      loop do
        size, body = body.split LINE_SPLIT, 2
        size = size.to_i 16

        decoded << body.byteslice(0, size)
        body = body.byteslice (size+2)..-1       # remove segment ending "\r\n"
        break if body.empty? || body.nil?
      end
      decoded
    end
  end
end
