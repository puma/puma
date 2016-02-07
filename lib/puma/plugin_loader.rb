require 'puma/plugin'

module Puma
  class UnknownPlugin < RuntimeError; end

  class PluginLoader
    def initialize
      @instances = []
    end

    def create(name)
      if cls = Plugins.find(name)
        plugin = cls.new(self)
        @instances << plugin
        return plugin
      end

      raise UnknownPlugin, "File failed to register properly named plugin"
    end

    def fire_starts(launcher)
      @instances.each do |i|
        if i.respond_to? :start
          i.start(launcher)
        end
      end
    end
  end

  class PluginRegistry
    def initialize
      @plugins = {}
    end

    def register(name, cls)
      @plugins[name] = cls
    end

    def find(name)
      name = name.to_s

      if cls = @plugins[name]
        return cls
      end

      begin
        require "puma/plugin/#{name}"
      rescue LoadError
        raise UnknownPlugin, "Unable to find plugin: #{name}"
      end

      if cls = @plugins[name]
        return cls
      end

      raise UnknownPlugin, "file failed to register a plugin"
    end
  end

  Plugins = PluginRegistry.new
end
