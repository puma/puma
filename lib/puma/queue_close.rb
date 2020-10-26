class ClosedQueueError < StandardError; end
module Puma

  # Queue#close was added in Ruby 2.3.
  # Add a simple implementation for earlier Ruby versions.
  #
  module QueueClose
    def initialize
      @closed = false
      super
    end
    def close
      @closed = true
    end
    def closed?
      @closed
    end
    def push(object)
      @closed ||= false
      raise ClosedQueueError if @closed
      super
    end
    alias << push
  end
  ::Queue.prepend QueueClose
end
