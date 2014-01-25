require "rbconfig"
require 'test/unit'
require 'puma/server'

require 'socket'

# UNIX sockets are not recommended on JRuby
# (or Windows)
unless defined?(JRUBY_VERSION) || RbConfig::CONFIG["host_os"] =~ /mingw|mswin/
  class TestPumaUnixSocket < Test::Unit::TestCase
  
    App = lambda { |env| [200, {}, ["Works"]] }
  
    Path = "test/puma.sock"
  
    def setup
      @server = Puma::Server.new App
      @server.add_unix_listener Path
      @server.run
    end
  
    def teardown
      @server.stop(true)
      File.unlink Path if File.exist? Path
    end
  
    def test_server
      sock = UNIXSocket.new Path
  
      sock << "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"
  
      expected = "HTTP/1.0 200 OK\r\nConnection: close\r\nContent-Length: 5\r\n\r\nWorks"
  
      assert_equal expected, sock.read(expected.size)
  
      sock.close
    end
  end
end
