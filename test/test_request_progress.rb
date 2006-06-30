# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

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
