# frozen_string_literal: true

require 'stringio'

module Puma
  class IOBuffer < StringIO
    def initialize
      super.binmode
    end

    def empty?
      length.zero?
    end

    def reset
      truncate 0
      rewind
    end

    def read
      rewind
      super.tap { |s| truncate 0; rewind }
    end

    # don't use, added just for existing CI tests
    alias_method :to_s, :string

    # before Ruby 2.5, `write` would only take one argument
    if RUBY_VERSION >= '2.5' && RUBY_ENGINE != 'truffleruby'
      alias_method :append, :write
    else
      def append(*strs)
        strs.each { |str| write str }
      end
    end
  end
end
