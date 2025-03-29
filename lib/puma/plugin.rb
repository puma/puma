# frozen_string_literal: true

module Puma
  class UnknownPlugin < RuntimeError; end

  class PluginLoader
    def initialize
      @instances = []
    end

    def create(name, path_override = nil)
      if cls = Plugins.find(name, path_override)
        plugin = cls.new
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
      @background = []
    end

    def register(name, cls)
      @plugins[name] = cls
    end

    def find(name, path_override = nil)
      name = name.to_s

      if cls = @plugins[name]
        return cls
      end

      begin
        require (path_override || "puma/plugin/#{name}")
      rescue LoadError
        raise UnknownPlugin, "Unable to find plugin: #{name}"
      end

      if cls = @plugins[name]
        return cls
      end

      raise UnknownPlugin, "file failed to register a plugin"
    end

    def add_background(blk)
      @background << blk
    end

    def fire_background
      @background.each_with_index do |b, i|
        Thread.new do
          Puma.set_thread_name "plgn bg #{i}"
          b.call
        end
      end
    end
  end

  Plugins = PluginRegistry.new

  class Plugin
    # Matches
    #  "C:/Ruby22/lib/ruby/gems/2.2.0/gems/puma-3.0.1/lib/puma/plugin/tmp_restart.rb:3:in `<top (required)>'"
    #  AS
    #  C:/Ruby22/lib/ruby/gems/2.2.0/gems/puma-3.0.1/lib/puma/plugin/tmp_restart.rb
    CALLER_FILE = /
      \A       # start of string
      .+       # file path (one or more characters)
      (?=      # stop previous match when
        :\d+     # a colon is followed by one or more digits
        :in      # followed by a colon followed by in
      )
    /x

    def self.extract_name(ary)
      path = ary.first[CALLER_FILE]

      m = %r!puma/plugin/([^/]*)\.rb$!.match(path)
      m[1]
    end

    # An optional `name_override` argument can be provided
    # to specify a custom name for the plugin, instead of
    # letting Puma automatically generate it based on the path.
    #
    def self.create(name_override = nil, &blk)
      name = name_override&.to_s || extract_name(caller)

      cls = Class.new(self)

      cls.class_eval(&blk)

      Plugins.register name, cls
    end

    def in_background(&blk)
      Plugins.add_background blk
    end
  end
end
