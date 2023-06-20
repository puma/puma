# frozen_string_literal: true

require 'socket'

module TestPuma

  RE_HOST_TO_IP = /\A\[|\]\z/o

  HOST4 = begin
    t = Socket.ip_address_list.select(&:ipv4_loopback?).map(&:ip_address)
      .uniq.sort(&:length)
    # puts "IPv4 Loopback #{t}"
    str = t.include?('127.0.0.1') ? +'127.0.0.1' : +"#{t.first}"
    str.define_singleton_method(:ip) { self }
    str.freeze
  end

  HOST6 = begin
    t = Socket.ip_address_list.select(&:ipv6_loopback?).map(&:ip_address)
      .uniq.sort(&:length)
    # puts "IPv6 Loopback #{t}"
    t.include?('::1') ? +'[::1]' : "[#{t.first}]"
    str = t.include?('::1') ? +'[::1]' : +"[#{t.first}]"
    str.define_singleton_method(:ip) { self.gsub RE_HOST_TO_IP, '' }
    str.freeze
  end

  LOCALHOST = ENV.fetch 'PUMA_CI_DFLT_HOST', 'localhost'

  if ENV['PUMA_CI_DFLT_IP'] =='IPv6'
    HOST     = HOST6
    ALT_HOST = HOST4
  else
    HOST     = HOST4
    ALT_HOST = HOST6
  end

  DARWIN = RUBY_PLATFORM.include? 'darwin'

  TOKEN = "xxyyzz"
end
