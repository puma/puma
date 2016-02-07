module Puma
  class UnknownPlugin < RuntimeError; end

  class PluginLoader
    def initialize
      @instances = []
    end

    def create(name)
      if cls = Plugins.find(name)
        plugin = cls.new(Plugin)
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

  class Plugin
    def self.extract_name(ary)
      path = ary.first.split(":").first

      m = %r!puma/plugin/([^/]*)\.rb$!.match(path)
      return m[1]
    end

    def self.create(&blk)
      name = extract_name(caller)

      cls = Class.new(self)

      cls.class_eval(&blk)

      Plugins.register name, cls
    end

    def initialize(loader)
      @loader = loader
    end

    def in_background(&blk)
      Thread.new(&blk)
    end

    def workers_supported?
      return false if Puma.jruby? || Puma.windows?
      true
    end
  end
end
