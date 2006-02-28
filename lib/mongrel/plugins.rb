require 'singleton'

module Mongrel
  class PluginManager
    include Singleton
    
    def initialize
      @plugins = URIClassifier.new
    end
    
    def load(path)
      Dir.chdir(path) do
        Dir["**/*.rb"].each do |rbfile|
          require rbfile
        end
      end
    end
    
    def register(category, name, klass)
      cat, ignored, map = @plugins.resolve(category)
      if not cat
        map = {name => klass}
        @plugins.register(category, map)
      else
        map[name] = klass
      end
    end
    
    
    def create(name, options = {})
      category, plugin, map = @plugins.resolve(name)
      if category and plugin and plugin.length > 0
        STDERR.puts "found: #{category} #{plugin} for #{name}"
        map[plugin].new(options)
      else
        raise "Plugin #{name} does not exist"
      end
    end
    
    def available
      map = {}
      @plugins.uris.each do |u| 
        cat, name, plugins = @plugins.resolve(u)
        map[cat] ||= []
        map[cat] += plugins.keys
      end

      return map
    end
    
  end

  class PluginBase
    
    def PluginBase.inherited(klass)
      
      PluginManager.instance.register(@@category, klass.to_s.downcase, klass)
    end
    
    def PluginBase.category=(category)
      @@category = category
    end
  end
  
  def Plugin(c)
    PluginBase.category = c
    PluginBase
  end
  
end




