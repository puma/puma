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


class MongrelDbgTest < Test::Unit::TestCase

  def test_base_handler_config
    config = Mongrel::Configurator.new :host => "localhost" do
      listener :port => 3111 do
        # 2 in front should run, but the sentinel shouldn't since dirhandler processes the request
        uri "/", :handler => plugin("/handlers/testplugin")
        uri "/", :handler => plugin("/handlers/testplugin")
        uri "/", :handler => Mongrel::DirHandler.new(".", load_mime_map("examples/mime.yaml"))
        uri "/", :handler => plugin("/handlers/sentinel")

        uri "/test", :handler => plugin("/handlers/testplugin")
        uri "/test", :handler => plugin("/handlers/testplugin")
        uri "/test", :handler => Mongrel::DirHandler.new(".", load_mime_map("examples/mime.yaml"))
        uri "/test", :handler => plugin("/handlers/sentinel")
        run
      end
    end

    res = Net::HTTP.get(URI.parse('http://localhost:3111/test'))
    assert res != nil, "Didn't get a response"
    assert $test_plugin_fired == 2, "Test filter plugin didn't run twice."


    res = Net::HTTP.get(URI.parse('http://localhost:3111/'))
    assert res != nil, "Didn't get a response"
    assert $test_plugin_fired == 4, "Test filter plugin didn't run 4 times."

    config.stop
    
    assert_raise Errno::ECONNREFUSED do
      res = Net::HTTP.get(URI.parse("http://localhost:3111/"))
    end
  end

end
