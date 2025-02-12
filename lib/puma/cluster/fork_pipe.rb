# frozen_string_literal: true

require "io/wait"

module Puma
  class Cluster
    class ForkPipeReader
      PAYLOAD_STRING = "q" # going with bigint out of learned fear of overflow
      PAYLOAD_SIZE = 4 # # of bytes in a q payload

      RESTART_SERVER = 0
      START_REFORK = -1
      AFTER_REFORK = -2

      # avoids allocation of objects while reading
      # only reads 1 payload at a time (minimize data loss if process exits unexpectedly)
      # NOT thread-safe, but concurrent access not required anywhere currently
      def initialize(pipe)
        @pipe = pipe
        @buffer = +""
        @payload = +""
      end

      def read
        @buffer.clear
        @payload.clear
        remaining = PAYLOAD_SIZE
        while remaining > 0
          case @pipe.read_nonblock(remaining, @buffer, exception: false)
          when :wait_readable
            @pipe.wait_readable
          when :wait_writable
            @pipe.wait_writable
          else
            @payload << @buffer
            remaining -= @buffer.bytesize
          end
        end
        @payload.unpack1(PAYLOAD_STRING)
      end

      def close
        @pipe.close
      end
    end

    class ForkPipeWriter < DelegateClass(IO)
      # not thread safe, no concurrency expected
      # minimize object allocation per loop
      def initialize(pipe)
        @pipe = pipe
        @payloads = []
        @buffer = +""
      end

      def <<(payload)
        @buffer.clear
        @payloads << payload
        @payloads.pack(ForkPipeReader::PAYLOAD_STRING, buffer: @buffer)
        @payloads.clear
        until @buffer.empty?
          case (written = @pipe.write_nonblock(@buffer, exception: false))
          when :wait_writable
            @pipe.wait_writable
          when :wait_readable
            @pipe.wait_readable
          when Integer
            @buffer = @buffer[written, ForkPipeReader::PAYLOAD_SIZE]
          end
        end
      end

      def start_refork
        self << ForkPipeReader::START_REFORK
      end

      def after_refork
        self << ForkPipeReader::AFTER_REFORK
      end

      def refork_workers(*indices)
        indices.each do |idx|
          self << idx
        end
      end

      def restart_server
        self << ForkPipeReader::RESTART_SERVER
      end

      def close
        @pipe.close
      end
    end
  end
end
