module Puma
  class IOBuffer
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
end
