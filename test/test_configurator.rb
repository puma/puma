# Mongrel Web Server - A Mostly Ruby Webserver and Library
#
# Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

require 'test/unit'
require 'mongrel'
require 'net/http'

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

        debug "/"
        setup_signals

        run_config(File.dirname(__FILE__) + "/../test/mongrel.conf")
        load_mime_map(File.dirname(__FILE__) + "/../examples/mime.yaml")

        run
      end
    end


    config.listeners.each do |host,listener| 
      assert listener.classifier.uris.length == 3, "Wrong number of registered URIs"
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
