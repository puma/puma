require 'test/unit'
require 'mongrel_config/init'

class CommandTest < Test::Unit::TestCase
  def setup
    @pmgr = GemPlugin::Manager.instance
  end

  def test_command_loaded
    assert @pmgr.create("/commands/configtool", "configtool not loaded")
  end

end


# these are only run if we're running on windows
if RUBY_PLATFORM =~ /mswin/
  require 'mongrel_config/win32'

  class Win32Test < Test::Unit::TestCase
    
    def test_list
      svcs = W32Support.list
      assert svcs.length > 0, "No services returned.  Make sure you have one mongrel installed."
    end

    def test_display_name
      svcs = W32Support.list
      svcs.each { |s| W32Support.display(s.service_name) }
    end

    def test_start_stop
      svcs = W32Support.list
      svcs.each { |s|
        puts "Starting #{W32Support.display(s.service_name)} (might take a while)"
        i = 1
        W32Support.start(s.service_name) do |status|
          print "Starting #{s.service_name}: #{status} (#{i} seconds)\r"
          sleep 1
          i += 1
        end

        W32Support.stop(s.service_name) do |status|
          puts "Stopping #{s.service_name}: #{status}"
          sleep 1
        end
      }
    end

  end
end

  
