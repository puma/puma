require 'test/unit'
require 'mongrel'

class ATestPlugin < Mongrel::Plugin "/stuff"
end

class First < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "First with options: #{options.inspect}"
  end
end

class Second < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "Second with options: #{options.inspect}"
  end
end

class Last < Mongrel::Plugin "/commands"
  def initialize(options = {})
    puts "Last with options: #{options.inspect}"
  end
end


include Mongrel

class PluginTest < Test::Unit::TestCase

  def setup
    @pmgr = PluginManager.instance
    @categories = ["/commands"]
    @names = ["/first", "/second", "/last", "/atestplugin"]
  end

  def test_load_plugins
    puts "#{@pmgr.available.inspect}"
    @pmgr.available.each {|cat,plugins|
      plugins.each do |p|
        puts "TEST: #{cat}#{p}"
        assert @names.include?(p)
      end
    }

    @pmgr.load
    @pmgr.available.each do |cat,plugins|
      plugins.each do |p|
        STDERR.puts "#{cat}#{p}"
        plugin = @pmgr.create("#{cat}#{p}", options={"name" => p})
      end
    end
  end

  def test_similar_uris

    @pmgr.register("/test", "/testme", ATestPlugin)
    @pmgr.register("/test2", "/testme", ATestPlugin)

    assert_equal @pmgr.create("/test/testme").class, ATestPlugin
    assert_equal @pmgr.create("/test2/testme").class, ATestPlugin

  end
end
