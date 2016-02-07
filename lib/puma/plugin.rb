require 'puma/plugin_loader'

module Puma
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
