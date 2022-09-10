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

require_relative "minitest/verbose"
require "minitest/autorun"
require "minitest/pride"
require "minitest/proveit"
require "minitest/stub_const"
require "net/http"
require_relative "helpers/apps"

Thread.abort_on_exception = true

$debugging_info = ''.dup
$debugging_hold = false   # needed for TestCLI#test_control_clustered
$test_case_timeout = ENV.fetch("TEST_CASE_TIMEOUT") do
  RUBY_ENGINE == "ruby" ? 45 : 60
end.to_i

require "puma"
require "puma/detect"

# used in various ssl test files, see test_puma_server_ssl.rb and
# test_puma_localhost_authority.rb
if Puma::HAS_SSL
  require 'puma/log_writer'
  class SSLLogWriterHelper < ::Puma::LogWriter
    attr_accessor :addr, :cert, :error

    def ssl_error(error, ssl_socket)
      self.error = error
      self.addr = ssl_socket.peeraddr.last rescue "<unknown>"
      self.cert = ssl_socket.peercert
    end
  end
end

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
  def self.call
    TCPServer.open('127.0.0.1', 0) do |server|
      server.connect_address.ip_port
    end
  end
end

require "timeout"
module TimeoutEveryTestCase
  # our own subclass so we never confused different timeouts
  class TestTookTooLong < Timeout::Error
  end

  def run
    with_info_handler do
      time_it do
        capture_exceptions do
          ::Timeout.timeout($test_case_timeout, TestTookTooLong) do
            before_setup; setup; after_setup
            self.send self.name
          end
        end

        capture_exceptions do
          ::Timeout.timeout($test_case_timeout, TestTookTooLong) do
            Minitest::Test::TEARDOWN_METHODS.each { |hook| self.send hook }
          end
        end
        if respond_to? :clean_tmp_paths
          clean_tmp_paths
        end
      end
    end

    Minitest::Result.from self # per contract
  end
end

Minitest::Test.prepend TimeoutEveryTestCase
if ENV['CI']
  require 'minitest/retry'
  Minitest::Retry.use!
end

module TestSkips

  HAS_FORK = ::Process.respond_to? :fork
  UNIX_SKT_EXIST = Object.const_defined? :UNIXSocket

  MSG_FORK = "Kernel.fork isn't available on #{RUBY_ENGINE} on #{RUBY_PLATFORM}"
  MSG_UNIX = "UNIXSockets aren't available on the #{RUBY_PLATFORM} platform"
  MSG_AUNIX = "Abstract UNIXSockets aren't available on the #{RUBY_PLATFORM} platform"

  SIGNAL_LIST = Signal.list.keys.map(&:to_sym) - (Puma.windows? ? [:INT, :TERM] : [])

  JRUBY_HEAD = Puma::IS_JRUBY && RUBY_DESCRIPTION.include?('SNAPSHOT')

  DARWIN = RUBY_PLATFORM.include? 'darwin'

  TRUFFLE = RUBY_ENGINE == 'truffleruby'
  TRUFFLE_HEAD = TRUFFLE && RUBY_DESCRIPTION.include?('-dev-')

  # usage: skip_unless_signal_exist? :USR2
  def skip_unless_signal_exist?(sig, bt: caller)
    signal = sig.to_s.sub(/\ASIG/, '').to_sym
    unless SIGNAL_LIST.include? signal
      skip "Signal #{signal} isn't available on the #{RUBY_PLATFORM} platform", bt
    end
  end

  # called with one or more params, like skip_if :jruby, :windows
  # optional suffix kwarg is appended to the skip message
  # optional suffix bt should generally not used
  def skip_if(*engs, suffix: '', bt: caller)
    engs.each do |eng|
      skip_msg = case eng
        when :darwin      then "Skipped if darwin#{suffix}"      if Puma::IS_OSX
        when :jruby       then "Skipped if JRuby#{suffix}"       if Puma::IS_JRUBY
        when :truffleruby then "Skipped if TruffleRuby#{suffix}" if TRUFFLE
        when :windows     then "Skipped if Windows#{suffix}"     if Puma::IS_WINDOWS
        when :ci          then "Skipped if ENV['CI']#{suffix}"   if ENV['CI']
        when :no_bundler  then "Skipped w/o Bundler#{suffix}"    if !defined?(Bundler)
        when :ssl         then "Skipped if SSL is supported"     if Puma::HAS_SSL
        when :fork        then "Skipped if Kernel.fork exists"   if HAS_FORK
        when :unix        then "Skipped if UNIXSocket exists"    if Puma::HAS_UNIX_SOCKET
        when :aunix       then "Skipped if abstract UNIXSocket"  if Puma.abstract_unix_socket?
        when :rack3       then "Skipped if Rack 3.x"             if Rack::RELEASE >= '3'
        else false
      end
      skip skip_msg, bt if skip_msg
    end
  end

  # called with only one param
  def skip_unless(eng, bt: caller)
    skip_msg = case eng
      when :darwin  then "Skip unless darwin"           unless Puma::IS_OSX
      when :jruby   then "Skip unless JRuby"            unless Puma::IS_JRUBY
      when :windows then "Skip unless Windows"          unless Puma::IS_WINDOWS
      when :mri     then "Skip unless MRI"              unless Puma::IS_MRI
      when :ssl     then "Skip unless SSL is supported" unless Puma::HAS_SSL
      when :fork    then MSG_FORK                       unless HAS_FORK
      when :unix    then MSG_UNIX                       unless Puma::HAS_UNIX_SOCKET
      when :aunix   then MSG_AUNIX                      unless Puma.abstract_unix_socket?
      when :rack3   then "Skipped unless Rack >= 3.x"   unless ::Rack::RELEASE >= '3'
      else false
    end
    skip skip_msg, bt if skip_msg
  end
end

Minitest::Test.include TestSkips

class Minitest::Test

  REPO_NAME = ENV['GITHUB_REPOSITORY'] ? ENV['GITHUB_REPOSITORY'][/[^\/]+\z/] : 'puma'

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
  if !$debugging_hold && ENV['PUMA_TEST_DEBUG']
    out = $debugging_info.strip
    unless out.empty?
      dash = "\u2500"
      wid = ENV['GITHUB_ACTIONS'] ? 88 : 90
      txt = " Debugging Info #{dash * 2}".rjust wid, dash
      if ENV['GITHUB_ACTIONS']
        puts "", "##[group]#{txt}", out, dash * wid, '', '::[endgroup]'
      else
        puts "", txt, out, dash * wid, ''
      end
    end
  end
end

module AggregatedResults
  def aggregated_results(io)
    filtered_results = results.dup

    if options[:verbose]
      skips = filtered_results.select(&:skipped?)
      unless skips.empty?
        dash = "\u2500"
        io.puts '', "Skips:"
        hsh = skips.group_by { |f| f.failures.first.error.message }
        hsh_s = {}
        hsh.each { |k, ary|
          hsh_s[k] = ary.map { |s|
            [s.source_location, s.klass, s.name]
          }.sort_by(&:first)
        }
        num = 0
        hsh_s = hsh_s.sort.to_h
        hsh_s.each { |k,v|
          io.puts " #{k} #{dash * 2}".rjust 90, dash
          hsh_1 = v.group_by { |i| i.first.first }
          hsh_1.each { |k1,v1|
            io.puts "  #{k1[/\/test\/(.*)/,1]}"
            v1.each { |item|
              num += 1
              io.puts format("    %3s %-5s #{item[1]} #{item[2]}", "#{num})", ":#{item[0][1]}")
            }
            puts ''
          }
        }
      end
    end

    filtered_results.reject!(&:skipped?)

    io.puts "Errors & Failures:" unless filtered_results.empty?

    filtered_results.each_with_index { |result, i|
      io.puts "\n%3d) %s" % [i+1, result]
    }
    io.puts
    io
  end
end
Minitest::SummaryReporter.prepend AggregatedResults
