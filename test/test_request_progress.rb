
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
require 'net/http'
require File.dirname(__FILE__) + '/testhelp.rb'


class UploadBeginHandler < Mongrel::HttpHandler
  attr_reader :request_began, :request_progressed, :request_processed

  def initialize
    @request_notify = true
  end

  def request_begins(params)
    @request_began = true
  end

  def request_progress(params,len,total)
    @request_progressed = true
  end

  def process(request, response)
    @request_processed = true
    response.start do |head,body|
      body.write("test")
    end
  end

end


class RequestProgressTest < Test::Unit::TestCase

  def setup
    @server = Mongrel::HttpServer.new("127.0.0.1", 9998)
    @handler = UploadBeginHandler.new
    @server.register("/upload", @handler)
    @server.run
  end

  def teardown
    @server.stop
  end

  def test_begin_end_progress
    Net::HTTP.get("localhost", "/upload", 9998)
    assert @handler.request_began
    assert @handler.request_progressed
    assert @handler.request_processed
  end

end
