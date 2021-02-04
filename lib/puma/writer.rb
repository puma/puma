# frozen_string_literal: true

module Puma
  class Writer
    class << self
      def write(io, data)
        case data.class
        when Array
          write_array(io, data)
        when String
          write_str(io, data)
        else
          write_str(io, data.to_s)
        end
      end

      def write_str(io, str)
        n = 0

        while true
          handle_errors(io) do
            n = io.write str
          end

          return if n == str.bytesize

          str = str.byteslice(n..-1)
        end
      end

      def write_array(io, array)
        n = 0

        while true
          handle_errors(io) do
            n = io.write(*array)
          end

          return if n == array_bytesize(array)

          array = array_byteslice_at_byte(array, n)
        end
      end

      private

      def handle_errors(io)
        yield
      rescue Errno::EAGAIN, Errno::EWOULDBLOCK
        if !IO.select(nil, [io], nil, WRITE_TIMEOUT)
          raise ConnectionError, "Socket timeout writing data"
        end

        retry
      rescue Errno::EPIPE, SystemCallError, IOError
        raise ConnectionError, "Socket timeout writing data"
      end

      def array_bytesize(array)
        array.sum(&:bytesize)
      end

      def array_byteslice_at_byte(array, byte)
        remaining = byte

        array.drop_while do |str|
          remaining -= str.bytesize
          remaining > 0
        end

        array[0] = array[0].byteslice(remaining)

        array
      end
    end
  end
end
