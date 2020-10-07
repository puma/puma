# Queue#close was added in Ruby 2.3.
# Add a simple implementation for earlier Ruby versions.
unless Queue.instance_methods.include?(:close)
  class ClosedQueueError < StandardError; end
  module Puma
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
        raise ClosedQueueError if @closed
        super
      end
      alias << push
    end
    Queue.prepend QueueClose
  end
end
