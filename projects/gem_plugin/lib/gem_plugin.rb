require 'singleton'
require 'rubygems'

# Implements a dynamic plugin loading, configuration, and discovery system
# based on RubyGems and a simple additional name space that looks like a URI.
#
# A plugin is created and put into a category with the following code:
#
#  class MyThing < GemPlugin::Plugin "/things"
#    ...
#  end
# 
# What this does is sets up your MyThing in the plugin registry via GemPlugin::Manager.
# You can then later get this plugin with GemPlugin::Manager.create("/things/mything")
# and can also pass in options as a second parameter.
#
# This isn't such a big deal, but the power is really from the GemPlugin::Manager.load
# method.  This method will go through the installed gems and require_gem any
# that depend on the gem_plugin RubyGem.  You can arbitrarily include or exclude
# gems based on what they also depend on, thus letting you load these gems when appropriate.
#
# Since this system was written originally for the Mongrel project that'll be the
# best examle of using it.
#
# Imagine you have a neat plugin for Mongrel called snazzy_command that give the
# mongrel_rails a new command snazzy (like:  mongrel_rails snazzy).  You'd like
# people to be able to grab this plugin if they want and use it, because it's snazzy.
#
# First thing you do is create a gem of your project and make sure that it depends
# on "mongrel" AND "gem_plugin".  This signals to the GemPlugin system that this is
# a plugin for mongrel.
#
# Next you put this code into a file like lib/init.rb (can be anything really):
#
#  class Snazzy < GemPlugin::Plugin "/commands"
#    ...
#  end
#  
# Then when you create your gem you have the following bits in your Rakefile:
#
#  spec.add_dependency('mongrel', '>= 0.3.9')
#  spec.add_dependency('gem_plugin', '>= 0.1')
#  spec.autorequire = 'init.rb'
#
# Finally, you just have to now publish this gem for people to install and Mongrel
# will "magically" be able to install it.
#
# The "magic" part though is pretty simple and done via the GemPlugin::Manager.load
# method.  Read that to see how it is really done.
module GemPlugin

  EXCLUDE = true
  INCLUDE = false
  
  # This class is used by people who use gem plugins (but don't necessarily make them)
  # to add plugins to their own systems.  It provides a way to load plugins, list them,
  # and create them as needed.
  #
  # It is a singleton so you use like this:  GemPlugins::Manager.instance.load
  class Manager
    include Singleton

    def initialize
      @plugins = {}
      @loaded_gems = []
    end


    # Responsible for going through the list of available gems and loading 
    # any plugins requested.  It keeps track of what it's loaded already
    # and won't load them again.
    #
    # It accepts one parameter which is a hash of gem depends that should include
    # or exclude a gem from being loaded.  A gem must depend on gem_plugin to be
    # considered, but then each system has to add it's own INCLUDE to make sure
    # that only plugins related to it are loaded.
    #
    # An example again comes from Mongrel.  In order to load all Mongrel plugins:
    #
    #  GemPlugin::Manager.instance.load "mongrel" => GemPlugin::INCLUDE
    #
    # Which will load all plugins that depend on mongrel AND gem_plugin.  Now, one
    # extra thing we do is we delay loading Rails Mongrel plugins until after rails
    # is configured.  Do do this the mongrel_rails script has:
    #
    #  GemPlugin::Manager.instance.load "mongrel" => GemPlugin::INCLUDE, "rails" => GemPlugin::EXCLUDE
    # The only thing to remember is that this is saying "include a plugin if it
    # depends on gem_plugin, mongrel, but NOT rails".  If a plugin also depends on other
    # stuff then it's loaded just fine.  Only gem_plugin, mongrel, and rails are
    # ever used to determine if it should be included.
    def load(needs = {})
      sdir = File.join(Gem.dir, "specifications")
      gems = Gem::SourceIndex.from_installed_gems(sdir)
      needs = needs.merge({"gem_plugin" => INCLUDE})

      gems.each do |path, gem|
        # don't load gems more than once
        next if @loaded_gems.include? gem.name        
        check = needs.dup

        # rolls through the depends and inverts anything it finds
        gem.dependencies.each do |dep|
          # this will fail if a gem is depended more than once
          if check.has_key? dep.name
            check[dep.name] = !check[dep.name]
          end
        end
        
        # now since excluded gems start as true, inverting them
        # makes them false so we'll skip this gem if any excludes are found
        if (check.select {|name,test| !test}).length == 0
          # looks like no needs were set to false, so it's good
          require_gem gem.name
          @loaded_gems << gem.name
        end

      end
    end


    # Not necessary for you to call directly, but this is
    # how GemPlugin::Base.inherited actually adds a 
    # plugin to a category.
    def register(category, name, klass)
      @plugins[category] ||= {}
      @plugins[category][name.downcase] = klass
    end
    
    # Resolves the given name (should include /category/name) to
    # find the plugin class and create an instance.  You can
    # pass a second hash option that is then given to the Plugin 
    # to configure it.
    def create(name, options = {})
      last_slash = name.rindex("/")
      category = name[0 ... last_slash]
      plugin = name[last_slash .. -1]

      map = @plugins[category]
      if not map
        raise "Plugin category #{category} does not exist"
      elsif not map.has_key? plugin
        raise "Plugin #{plugin} does not exist in category #{category}"
      else
        map[plugin].new(options)
      end
    end
    

    # Returns a map of URIs->{"name" => Plugin} that you can
    # use to investigate available handlers.
    def available
      return @plugins
    end
    
  end

  # This base class for plugins reallys does nothing
  # more than wire up the new class into the right category.
  # It is not thread-safe yet but will be soon.
  class Base
    
    attr_reader :options


    # See Mongrel::Plugin for an explanation.
    def Base.inherited(klass)
      name = "/" + klass.to_s.downcase
      Manager.instance.register(@@category, name, klass)
      @@category = nil
    end
    
    # See Mongrel::Plugin for an explanation.
    def Base.category=(category)
      @@category = category
    end

    def initialize(options = {})
      @options = options
    end

  end
  
  # This nifty function works with the GemPlugin::Base to give you
  # the syntax:
  #
  #  class MyThing < GemPlugin::Plugin "/things"
  #    ...
  #  end
  #
  # What it does is temporarily sets the GemPlugin::Base.category, and then
  # returns GemPlugin::Base.  Since the next immediate thing Ruby does is
  # use this returned class to create the new class, GemPlugin::Base.inherited
  # gets called.  GemPlugin::Base.inherited then uses the set category, class name,
  # and class to register the plugin in the right way.
  def GemPlugin::Plugin(c)
    Base.category = c
    Base
  end

end




