require 'test/unit'
require 'mongrel'


include Mongrel

class PluginTest < Test::Unit::TestCase

  def setup
    @pmgr = PluginManager.instance
    @categories = ["/commands"]
    @names = ["FirstCommand", "SecondCommand", "LastCommands"]
  end

  def test_load_plugins
    @pmgr.load(File.join(File.dirname(__FILE__),"plugins"))
    puts "#{@pmgr.available.inspect}"
    @pmgr.available.each {|cat,plugins|
      plugins.each do |p|
        puts "TEST: #{cat}/#{p}"
        assert @names.include?(p)
      end
    }

    @pmgr.available.each do |name|
      plugin = @pmgr.create(name, options={"name" => name})
    end
  end
  
end
