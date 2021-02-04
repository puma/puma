# frozen_string_literal: true

module Puma
  class IOBuffer < Array
    def bytesize
      sum(&:bytesize)
    end

    alias reset clear
    alias size bytesize
    alias to_s join
  end
end
