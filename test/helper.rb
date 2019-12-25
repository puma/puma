# frozen_string_literal: true
# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw

if %w(2.2.7 2.2.8 2.2.9 2.2.10 2.3.4 2.4.1).include? RUBY_VERSION
  begin
    require 'stopgap_13632'
  rescue LoadError
    puts "For test stability, you must install the stopgap_13632 gem."
    exit(1)
  end
end

require "net/http"
require "timeout"
require "minitest/autorun"
require "minitest/pride"
require "minitest/proveit"
require_relative "helpers/apps"

$LOAD_PATH << File.expand_path("../../lib", __FILE__)
Thread.abort_on_exception = true

$debugging_info = ''.dup
$debugging_hold = false    # needed for TestCLI#test_control_clustered

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
  @mutex = Mutex.new

  def self.call
    @mutex.synchronize {
      @port += 1
      @port = 3307 if @port == 3306  # MySQL on Actions
      @port
    }
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

module TestSkips

  # usage: skip NO_FORK_MSG unless HAS_FORK
  # windows >= 2.6 fork is not defined, < 2.6 fork raises NotImplementedError
  HAS_FORK = ::Process.respond_to? :fork
  NO_FORK_MSG = "Kernel.fork isn't available on the #{RUBY_PLATFORM} platform"

  # socket is required by puma
  # usage: skip UNIX_SKT_MSG unless UNIX_SKT_EXIST
  UNIX_SKT_EXIST = Object.const_defined? :UNIXSocket
  UNIX_SKT_MSG = "UnixSockets aren't available on the #{RUBY_PLATFORM} platform"

  SIGNAL_LIST = Signal.list.keys.map(&:to_sym) - (Puma.windows? ? [:INT, :TERM] : [])

  # usage: skip_unless_signal_exist? :USR2
  def skip_unless_signal_exist?(sig, bt: caller)
    signal = sig.to_s.sub(/\ASIG/, '').to_sym
    unless SIGNAL_LIST.include? signal
      skip "Signal #{signal} isn't available on the #{RUBY_PLATFORM} platform", bt
    end
  end

  # called with one or more params, like skip_on :jruby, :windows
  # optional suffix kwarg is appended to the skip message
  # optional suffix bt should generally not used
  def skip_on(*engs, suffix: '', bt: caller)
    skip_msg = false
    engs.each do |eng|
      skip_msg = case eng
        when :darwin   then "Skipped on darwin#{suffix}"    if RUBY_PLATFORM[/darwin/]
        when :jruby    then "Skipped on JRuby#{suffix}"     if Puma.jruby?
        when :windows  then "Skipped on Windows#{suffix}"   if Puma.windows?
        when :ci       then "Skipped on ENV['CI']#{suffix}" if ENV["CI"]
        when :no_bundler then "Skipped w/o Bundler#{suffix}"  if !defined?(Bundler)
        else false
      end
      skip skip_msg, bt if skip_msg
    end
  end

  # called with only one param
  def skip_unless(eng, bt: caller)
    skip_msg = case eng
      when :darwin  then "Skip unless darwin"  unless RUBY_PLATFORM[/darwin/]
      when :jruby   then "Skip unless JRuby"   unless Puma.jruby?
      when :windows then "Skip unless Windows" unless Puma.windows?
      else false
    end
    skip skip_msg, bt if skip_msg
  end
end

Minitest::Test.include TestSkips

class Minitest::Test
  def self.run(reporter, options = {}) # :nodoc:
    prove_it!
    super
  end

  def full_name
    "#{self.class.name}##{name}"
  end
end

Minitest.after_run do
  # needed for TestCLI#test_control_clustered
  unless $debugging_hold
    out = $debugging_info.strip
    unless out.empty?
      puts "", " Debugging Info".rjust(75, '-'),
        out, '-' * 75, ""
    end
  end
end
