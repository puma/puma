# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

if %w(2.2.7 2.2.8 2.2.9 2.2.10 2.3.4 2.4.1).include? RUBY_VERSION
  begin
    require 'stopgap_13632'
  rescue LoadError
  end
end

begin
  require "bundler/setup"
  # bundler/setup may not load bundler
  require "bundler" unless Bundler.const_defined?(:ORIGINAL_ENV)
rescue LoadError
  warn "Failed to load bundler ... this should only happen during package building"
end

require "net/http"
require "timeout"
require "minitest/autorun"
require "minitest/pride"

$LOAD_PATH << File.expand_path("../../lib", __FILE__)
Thread.abort_on_exception = true

require "puma"
require "puma/events"
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

module UniquePort
  @port  = 3211

  def self.call
    @port += 1
    @port
  end
end

module TimeoutEveryTestCase
  # our own subclass so we never confused different timeouts
  class TestTookTooLong < Timeout::Error
  end

  def run(*)
    ::Timeout.timeout(Puma.jruby? ? 120 : 60, TestTookTooLong) { super }
  end
end

if ENV['CI']
  Minitest::Test.prepend TimeoutEveryTestCase

  require 'minitest/retry'
  Minitest::Retry.use!
end

module SkipTestsBasedOnRubyEngine
  # called with one or more params, like skip_on :jruby, :windows
  # optional suffix kwarg is appended to the skip message
  # optional suffix bt should generally not used
  def skip_on(*engs, suffix: '', bt: caller)
    skip_msg = false
    engs.each do |eng|
      skip_msg = case eng
        when :jruby    then "Skipped on JRuby#{suffix}"     if Puma.jruby?
        when :windows  then "Skipped on Windows#{suffix}"   if Puma.windows?
        when :appveyor then "Skipped on Appveyor#{suffix}"  if ENV["APPVEYOR"]
        when :ci       then "Skipped on ENV['CI']#{suffix}" if ENV["CI"]
        else false
      end
      skip skip_msg, bt if skip_msg
    end
  end

  # called with only one param
  def skip_unless(eng, bt: caller)
    skip_msg = case eng
      when :jruby   then "Skip unless JRuby"   unless Puma.jruby?
      when :windows then "Skip unless Windows" unless Puma.windows?
      else false
    end
    skip skip_msg, bt if skip_msg
  end
end

Minitest::Test.include SkipTestsBasedOnRubyEngine
