require 'singleton'
require 'rubygems'

module Mongrel

  # Implements the main method of managing plugins for Mongrel.
  # "Plugins" in this sense are any classes which get registered
  # with Mongrel for possible use when it's operating.  These can
  # be Handlers, Commands, or other classes.  When you create a 
  # Plugin you register it into a URI-like namespace that makes
  # it easy for you (and others) to reference it later during
  # configuration.
  #
  # PluginManager is used as nothing more than a holder of all the
  # plugins that have registered themselves.  Let's say you have:
  #
  #  class StopNow < Plugin "/commands"
  #   ...
  #  end
  #
  # Then you can get at this plugin with:
  #
  #  cmd = PluginManager.create("/commands/stopnow")
  #
  # The funky syntax for StopNow is a weird trick borrowed from
  # the Camping framework. See the Mongrel::Plugin *function* (yes,
  # function).  What this basically does is register it 
  # into the namespace for plugins at /commands.  You could go
  # as arbitrarily nested as you like.
  #
  # Why this strange almost second namespace?  Why not just use
  # the ObjectSpace and/or Modules?  The main reason is speed and
  # to avoid cluttering the Ruby namespace with what is really a 
  # configuration statement.  This lets implementors put code 
  # into the Ruby structuring they need, and still have Plugins
  # available to Mongrel via simple URI-like names.
  #
  # The alternative (as pluginfactory does it) is to troll through
  # ObjectSpace looking for stuff that *might* be plugins every time
  # one is needed.  This alternative also means that you are stuck
  # naming your commands in specific ways and putting them in specific
  # modules in order to configure how Mongrel should use them.
  #
  # One downside to this is that you need to subclass plugin to 
  # make it work.  In this case use mixins to add other functionality.
  class PluginManager
    include Singleton
    
    def initialize
      @plugins = URIClassifier.new
      @loaded_gems = []
    end

    # Loads all the rubygems that depend on Mongrel so that they
    # can be configured into the plugins system.  This works by
    # checking if the gem depends on Mongrel, and then doing require_gem.
    # Since only plugins will configure themselves as plugins then 
    # everything is safe.
    #
    # You can also specify an alternative load path from the official
    # system gems location.  For example you can do the following:
    #
    #  mkdir mygems
    #  gem install -i mygems fancy_plugin
    #  mongrel_rails -L mygems start
    #
    # Which installs the fancy_plugin to your mygems directory and then 
    # tells mongrel_rails to load from mygems instead.
    #
    # The excludes list is used to prevent mongrel from loading gem plugins
    # that aren't ready yet.  In the mongrel_rails script this is used to
    # load gems that might need rails configured after rails is ready.
    def load(load_path = nil, excludes=[])
      sdir = File.join(load_path || Gem.dir, "specifications")
      gems = Gem::SourceIndex.from_installed_gems(sdir)
      
      gems.each do |path, gem|
        found_one = false
        gem.dependencies.each do |dep|
          # don't load excluded or already loaded gems
          if excludes.include? dep.name or @loaded_gems.include? gem.name
            found_one = false
            break
          elsif dep.name == "mongrel"
            found_one = true
          end
        end

        if found_one
          STDERR.puts "loading #{gem.name}"
          require_gem gem.name
          @loaded_gems << gem.name
        end

      end
    end


    # Not necessary for you to call directly, but this is
    # how Mongrel::PluginBase.inherited actually adds a 
    # plugin to a category.
    def register(category, name, klass)
      cat, ignored, map = @plugins.resolve(category)
      
      if not cat or ignored.length > 0
        map = {name => klass}
        @plugins.register(category, map)
      elsif not map
        raise "Unknown category #{category}"
      else
        map[name] = klass
      end
    end
    
    # Resolves the given name (should include /category/name) to
    # find the plugin class and create an instance.  It uses
    # the same URIClassifier that the rest of Mongrel does so it
    # is fast.
    def create(name, options = {})
      category, plugin, map = @plugins.resolve(name)

      if category and plugin and plugin.length > 0 and map[plugin]
        map[plugin].new(options)
      else
        raise "Plugin #{name} does not exist"
      end
    end
    
    # Returns a map of URIs->[handlers] that you can
    # use to investigate available handlers.
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

  # This base class for plugins reallys does nothing
  # more than wire up the new class into the right category.
  # It is not thread-safe yet but will be soon.
  class PluginBase
    
    attr_reader :options


    # See Mongrel::Plugin for an explanation.
    def PluginBase.inherited(klass)
      name = "/" + klass.to_s.downcase
      PluginManager.instance.register(@@category, name, klass)
      @@category = nil
    end
    
    # See Mongrel::Plugin for an explanation.
    def PluginBase.category=(category)
      @@category = category
    end

    def initialize(options = {})
      @options = options
    end

  end
  
  # This nifty function works with the PluginBase to give you
  # the syntax:
  #
  #  class MyThing < Plugin "/things"
  #    ...
  #  end
  #
  # What it does is temporarily sets the PluginBase.category, and then
  # returns PluginBase.  Since the next immediate thing Ruby does is
  # use this returned class to create the new class, PluginBase.inherited
  # gets called.  PluginBase.inherited then uses the set category, class name,
  # and class to register the plugin in the right way.
  def Mongrel::Plugin(c)
    PluginBase.category = c
    PluginBase
  end
  
end




