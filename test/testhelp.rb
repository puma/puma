# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

require 'rubygems'
require 'test/unit'
require 'net/http'
require 'digest/sha1'
require 'uri'
require 'stringio'

require 'puma'
require 'puma/detect'

# Either takes a string to do a get request against, or a tuple of [URI, HTTP] where
# HTTP is some kind of Net::HTTP request object (POST, HEAD, etc.)
def hit(uris)
  results = []
  uris.each do |u|
    res = nil

    if u.kind_of? String
      res = Net::HTTP.get(URI.parse(u))
    else
      url = URI.parse(u[0])
      res = Net::HTTP.new(url.host, url.port).start {|h| h.request(u[1]) }
    end

    assert res != nil, "Didn't get a response: #{u}"
    results << res
  end

  return results
end

module TimeoutEveryTestCase
  def run(*args)
    if !!ENV['CI']
      Timeout.timeout(60) { super }
    else
      super
    end
  end
end
Test::Unit::TestCase.prepend TimeoutEveryTestCase

module OmitTestsBasedOnRubyEngine
  def omit_on_jruby
    omit "Omitted on JRuby" if Puma.jruby?
  end
end
Test::Unit::TestCase.prepend OmitTestsBasedOnRubyEngine
