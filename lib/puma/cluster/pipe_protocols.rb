# frozen_string_literal: true

module Puma
  class Cluster
    module PipeProtocols
      module Fork
        @read_buffer = +""
        @write_buffer = []

        PAYLOAD_STRING = "l"
        PAYLOAD_SIZE = 4

        # This value is used to signal that the pipe should not be read anymore
        STOP_READING = -1

        def self.read_from(pipe)
          payload = pipe.read(PAYLOAD_SIZE, @read_buffer).unpack1(PAYLOAD_STRING)
          return nil if payload == STOP_READING
          payload
        ensure
          @read_buffer.clear
        end

        def self.write_to(pipe, value:)
          @write_buffer << value
          pipe.write(@write_buffer.pack(PAYLOAD_STRING))
        ensure
          @write_buffer.clear
        end
      end
    end
  end
end
