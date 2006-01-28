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
    resp.body.write("test")
    resp.finished

    assert out.length > 0, "output didn't have data"
  end

  def test_response_200
    io = StringIO.new
    resp = HttpResponse.new(io)
    resp.start do |head,out|
      head["Accept"] = "text/plain"
      out.write("tested")
      out.write("hello!")
    end
    assert io.length > 0, "output didn't have data"
  end

  def test_response_404
    io = StringIO.new

    resp = HttpResponse.new(io)
    resp.start(404) do |head,out|
      head['Accept'] = "text/plain"
      out.write("NOT FOUND")
    end

    assert io.length > 0, "output didn't have data"
  end

end

