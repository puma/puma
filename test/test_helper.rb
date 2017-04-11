# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

begin
  require "bundler/setup"
rescue LoadError
  warn "Failed to load bundler ... this should only happen during package building"
end

require "net/http"
require "timeout"
require "minitest/autorun"
require "minitest/pride"

$LOAD_PATH << File.expand_path("../../lib", __FILE__)

require "puma"
require "puma/detect"

# Either takes a string to do a get request against, or a tuple of [URI, HTTP] where
# HTTP is some kind of Net::HTTP request object (POST, HEAD, etc.)
def hit(uris)
  uris.map do |u|
    response =
      if u.kind_of? String
        Net::HTTP.get(URI.parse(u))
      else
        url = URI.parse(u[0])
        Net::HTTP.new(url.host, url.port).start {|h| h.request(u[1]) }
      end

    assert response, "Didn't get a response: #{u}"
    response
  end
end

module TimeoutEveryTestCase
  def run(*)
    if !!ENV['CI']
      ::Timeout.timeout(60) { super }
    else
      super
    end
  end
end

Minitest::Test.prepend TimeoutEveryTestCase

module SkipTestsBasedOnRubyEngine
  def skip_on_jruby
    skip "Skipped on JRuby" if Puma.jruby?
  end
end

Minitest::Test.include SkipTestsBasedOnRubyEngine
