# Mongrel Web Server - A Mostly Ruby HTTP server and Library
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
require 'benchmark'

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

    resp.finished
    assert io.length > 0, "output didn't have data"
  end

  def test_response_404
    io = StringIO.new

    resp = HttpResponse.new(io)
    resp.start(404) do |head,out|
      head['Accept'] = "text/plain"
      out.write("NOT FOUND")
    end

    resp.finished
    assert io.length > 0, "output didn't have data"
  end

  def test_response_file
    contents = "PLAIN TEXT\r\nCONTENTS\r\n"
    require 'tempfile'
    tmpf = Tempfile.new("test_response_file")
    tmpf.binmode
    tmpf.write(contents)
    tmpf.rewind

    io = StringIO.new
    resp = HttpResponse.new(io)
    resp.start(200) do |head,out|
      head['Content-Type'] = 'text/plain'
      resp.send_header
      resp.send_file(tmpf.path)
    end
    io.rewind
    tmpf.close
    
    assert io.length > 0, "output didn't have data"
    assert io.read[-contents.length..-1] == contents, "output doesn't end with file payload"
  end
end

