require 'test/unit'
require 'mongrel'

include Mongrel

class ResponseTest < Test::Unit::TestCase
  
  def test_response_headers
    out = StringIO.new
    resp = HttpResponse.new(out)
    resp.status = 200
    resp.header["Accept"] = "text/plain"
    resp.header["X-Whatever"] = "stuff"
    resp.out.write("test")
    resp.finished

    out.rewind
    puts out.read
  end

  def test_response_200
    io = StringIO.new
    resp = HttpResponse.new(io)
    resp.start do |head,out|
      head["Accept"] = "text/plain"
      out.write("tested")
      out.write("hello!")
    end

    io.rewind
    puts io.read
  end

  def test_response_404
    io = StringIO.new

    resp = HttpResponse.new(io)
    resp.start(404) do |head,out|
      head['Accept'] = "text/plain"
      out.write("NOT FOUND")
    end

    io.rewind
    puts io.read
  end

end

