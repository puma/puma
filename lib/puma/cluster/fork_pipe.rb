# frozen_string_literal: true

require "io/wait"

module Puma
  class Cluster
    class ForkPipeReader
      PAYLOAD_STRING = "q" # going with bigint out of learned fear of overflow
      PAYLOAD_SIZE = 8 # # of bytes in a q payload

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
        @payload.clear
        @pipe.read(PAYLOAD_SIZE, @payload)
        @payload.unpack1(PAYLOAD_STRING)
      end

      def close
        @pipe.close
      end

      def wait_readable
        @pipe.wait_readable
      end
    end

    class ForkPipeWriter
      # not thread safe, no concurrency expected
      # minimize object allocation per loop
      def initialize(pipe)
        @pipe = pipe
        @payloads = []
        @buffer = +""
      end

      def write(payload)
        @buffer.clear
        @payloads << payload
        @payloads.pack(ForkPipeReader::PAYLOAD_STRING, buffer: @buffer)
        @payloads.clear
        @pipe.write(@buffer)
      end

      def start_refork
        self.write ForkPipeReader::START_REFORK
      end

      def after_refork
        self.write ForkPipeReader::AFTER_REFORK
      end

      def refork_workers(*indices)
        indices.each do |idx|
          self.write idx
        end
      end

      def restart_server
        self.write ForkPipeReader::RESTART_SERVER
      end

      def stop
        self.write ForkPipeReader::STOP
      end

      def close
        @pipe.close
      end
    end
  end
end
