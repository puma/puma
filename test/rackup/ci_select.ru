# frozen_string_literal: true

# Generates a response with various body types and sizes, set via ENV['CI_BODY_CONF'] or
# `Body-Conf` request header.
# See 'CI - test/rackup/ci-*.ru files' or docs/test_rackup_ci_files.md

require 'securerandom'
require 'tmpdir'

headers = {}
headers['Content-Type'] = 'text/plain; charset=utf-8'.freeze
25.times { |i| headers["X-My-Header-#{i}"] = SecureRandom.hex(25) }

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'
hdr_content_length = 'Content-Length'

# length = 1018  bytesize = 1024
str_1kb = "──#{SecureRandom.hex 507}─\n".freeze

fn_format = "#{Dir.tmpdir}/.puma_response_body_io/body_io_%04d.txt".freeze

body_types = %w[a c i s].freeze

cache_array   = {}
cache_chunked = {}
cache_string  = {}

run lambda { |env|
  info = if (dly = env[hdr_dly])
    hash_key = +"#{dly},"
    sleep dly.to_f
    +"#{Process.pid}\nHello World\nSlept #{dly}\n"
  else
    hash_key = +","
    +"#{Process.pid}\nHello World\n"
  end
  info_len_adj = 1023 - info.bytesize

  body_conf = env[hdr_body_conf]

  if body_conf && body_conf.start_with?(*body_types)
    type = body_conf.slice!(0).to_sym
    len  = body_conf.to_i
  elsif body_conf
    type = :s
    len  = body_conf[/\d+\z/].to_i
  else   # default
    type = :s
    len  = 1
  end

  hash_key << len.to_s

  case type
  when :a      # body is an array
    headers[hdr_content_length] = (1_024 * len).to_s
    body = cache_array[hash_key] ||= begin
      temp = Array.new len, str_1kb
      temp[0] = info + str_1kb.byteslice(0, info_len_adj) + "\n"
      temp
    end
  when :c      # body is chunked
    headers.delete hdr_content_length
    body = cache_chunked[hash_key] ||= begin
      temp = Array.new len, str_1kb
      temp[0] = info + str_1kb.byteslice(0, info_len_adj) + "\n"
      temp.to_enum
    end
  when :i      # body is an io
    headers[hdr_content_length] = (1_024 * len).to_s
    fn = format fn_format, len
    body = File.open fn, 'rb'
  when :s      # body is a single string in an array
    headers[hdr_content_length] = (1_024 * len).to_s
    body = cache_string[hash_key] ||= begin
      info << str_1kb.byteslice(0, info_len_adj) << "\n" << (str_1kb * (len-1))
      [info]
    end
  end
  [200, headers, body]
}
