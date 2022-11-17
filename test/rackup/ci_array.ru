# frozen_string_literal: true

# Generates a response with array bodies, size set via ENV['CI_BODY_CONF'] or
# `Body-Conf` request header.
# See 'CI - test/rackup/ci-*.ru files' or docs/test_rackup_ci_files.md

require 'securerandom'

headers = {}
headers['Content-Type'] = 'text/plain; charset=utf-8'.freeze
25.times { |i| headers["X-My-Header-#{i}"] = SecureRandom.hex(25) }

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'

# length = 1018  bytesize = 1024
str_1kb = "──#{SecureRandom.hex 507}─\n".freeze

env_len = (t = ENV['CI_BODY_CONF']) ? t[/\d+\z/].to_i : 10

cache_array = {}

run lambda { |env|
  info = if (dly = env[hdr_dly])
    hash_key = +"#{dly},"
    sleep dly.to_f
    "#{Process.pid}\nHello World\nSlept #{dly}\n"
  else
    hash_key = +","
    "#{Process.pid}\nHello World\n"
  end
  info_len_adj = 1023 - info.bytesize

  len = (t = env[hdr_body_conf]) ? t[/\d+\z/].to_i : env_len

  hash_key << len.to_s

  headers[hdr_content_length] = (1_024 * len).to_s
  body = cache_array[hash_key] ||= begin
    temp = Array.new len, str_1kb
    temp[0] = info + str_1kb.byteslice(0, info_len_adj) + "\n"
    temp
  end
  [200, headers, body]
}
