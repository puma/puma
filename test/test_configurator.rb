require 'test/unit'
require 'mongrel'

$test_plugin_fired = 0

class TestPlugin < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def process(request, response)
    $test_plugin_fired += 1
  end
end


class Sentinel < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def process(request, response)
    raise "This Sentinel plugin shouldn't run."
  end
end


class ConfiguratorTest < Test::Unit::TestCase

  def test_base_handler_config
    config = Mongrel::Configurator.new :host => "localhost" do
      listener :port => 4501 do
        # 2 in front should run, but the sentinel shouldn't since dirhandler processes the request
        uri "/", :handler => plugin("/handlers/testplugin")
        uri "/", :handler => plugin("/handlers/testplugin")
        uri "/", :handler => Mongrel::DirHandler.new(".")
        uri "/", :handler => plugin("/handlers/testplugin")

        uri "/test", :handler => plugin("/handlers/testplugin")
        uri "/test", :handler => plugin("/handlers/testplugin")
        uri "/test", :handler => Mongrel::DirHandler.new(".")
        uri "/test", :handler => plugin("/handlers/testplugin")
        run
      end
    end


    config.listeners.each do |host,listener| 
      puts "Registered URIs: #{listener.classifier.uris.inspect}"
      assert listener.classifier.uris.length == 2, "Wrong number of registered URIs"
      assert listener.classifier.uris.include?("/"),  "/ not registered"
      assert listener.classifier.uris.include?("/test"), "/test not registered"
    end

    res = Net::HTTP.get(URI.parse('http://localhost:4501/test'))
    assert res != nil, "Didn't get a response"
    assert $test_plugin_fired == 3, "Test filter plugin didn't run 3 times."


    res = Net::HTTP.get(URI.parse('http://localhost:4501/'))
    assert res != nil, "Didn't get a response"
    assert $test_plugin_fired == 6, "Test filter plugin didn't run 6 times."

    config.stop
    
    assert_raise Errno::EBADF, Errno::ECONNREFUSED do
      res = Net::HTTP.get(URI.parse("http://localhost:4501/"))
    end
  end

end
