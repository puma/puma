require 'test/unit'
require 'test/testhelp'
require 'puma'
require 'rack/handler/puma'

class TestPumaUnixSocket < Test::Unit::TestCase
  def test_handler
    handler = Rack::Handler.get(:puma)
    assert_equal Rack::Handler::Puma, handler
    handler = Rack::Handler.get('Puma')
    assert_equal Rack::Handler::Puma, handler
  end
end

class TestPathHandler < Test::Unit::TestCase
  def app
    Proc.new {|env| @input = env; [200, {}, ["hello world"]]}
  end

  def setup
    @input = nil
  end

  def in_handler(app, options = {})
    options[:Port] ||= 9998
    @server = nil
    thread = Thread.new do
      Rack::Handler::Puma.run(app, options) do |s|
        @server = s
      end
    end
    thread.abort_on_exception = true

    # Wait for server to boot
    Timeout.timeout(10) do
      until @server && @server.running
        sleep 0.01
      end
    end
    yield @server
  ensure
    @server.stop(true) if @server
    thread.join if thread
  end


  def test_handler_boots
    in_handler(app) do |server|
      hit(["http://0.0.0.0:9998/test"])
      assert_equal("/test", @input["PATH_INFO"])
    end
  end

end
