module Puma
  if RUBY_PLATFORM == 'java'
    require 'java'
  
    class ByteArrayOutputStream < java.io.ByteArrayOutputStream
      field_reader :buf
    end

     # Conservative native JRuby/Java implementation of IOBuffer
     # backed by a ByteArrayOutputStream and conversion between
     # Ruby String and Java bytes
    class JavaIOBuffer
      BUF_DEFAULT_SIZE = 4096

      def initialize
        @buf = ByteArrayOutputStream.new(BUF_DEFAULT_SIZE)
      end

      def reset
        @buf.reset
      end

      def <<(str)
        bytes = str.to_java_bytes
        @buf.write(bytes, 0, bytes.length)
      end

      def append(*strs)
        strs.each { |s| self << s; }
      end

      def to_s
        String.from_java_bytes @buf.to_byte_array
      end

      alias_method :to_str, :to_s

      def used
        @buf.size
      end

      def capacity
        @buf.buf.length
      end
    end

    IOBuffer = JavaIOBuffer

  else

    class PortableIOBuffer
      def initialize
        @buf = ""
      end

      def reset
        @buf = ""
      end

      def <<(str)
        @buf << str
      end

      def append(*strs)
        strs.each { |s| @buf << s }
      end

      def to_s
        @buf
      end

      alias_method :to_str, :to_s

      def used
        @buf.size
      end

      def capacity
        @buf.size
      end
    end

    IOBuffer = PortableIOBuffer

  end
end
