# frozen_string_literal: true

module Puma

  # The default implement of an event sink object used by Server
  # for when certain kinds of events occur in the life of the server.
  # The methods available are the events that the Server fires.
  class Events

    def initialize
      @hooks = Hash.new { |h,k| h[k] = [] }
    end

    # Fire callbacks for the named hook
    def fire(hook, *args)
      @hooks[hook].each { |t| t.call(*args) }
    end

    # Register a callback for a given hook
    def register(hook, obj=nil, &blk)
      if obj and blk
        raise "Specify either an object or a block, not both"
      end

      h = obj || blk

      @hooks[hook] << h

      h
    end

    def on_booted(&block)
      register(:on_booted, &block)
    end

    def on_restart(&block)
      register(:on_restart, &block)
    end

    def on_stopped(&block)
      register(:on_stopped, &block)
    end

    def fire_on_booted!
      fire(:on_booted)
    end

    def fire_on_restart!
      fire(:on_restart)
    end

    def fire_on_stopped!
      fire(:on_stopped)
    end
  end
end
