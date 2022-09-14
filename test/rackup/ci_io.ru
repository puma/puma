# frozen_string_literal: true

# Generates a response with File/IO bodies, size set via ENV['CI_BODY_CONF'] or
# `Body-Conf` request header.
# See 'CI - test/rackup/ci-*.ru files' or docs/test_rackup_ci_files.md

require 'securerandom'
require 'tmpdir'

headers = {}
headers['Content-Type'] = 'text/plain; charset=utf-8'
25.times { |i| headers["X-My-Header-#{i}"] = SecureRandom.hex(25) }

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'
hdr_content_length = 'Content-Length'

env_len = (t = ENV['CI_BODY_CONF']) ? t[/\d+\z/].to_i : 10

tmp_folder = "#{Dir.tmpdir}/.puma_response_body_io"

unless Dir.exist? tmp_folder
  STDOUT.syswrite "\nNeeded files do not exist.  Run `TestPuma.create_io_files" \
    " contained in benchmarks/local/bench_base.rb\n"
  exit 1
end

fn_format = "#{tmp_folder}/body_io_%04d.txt"

run lambda { |env|
  if (dly = env[hdr_dly])
    sleep dly.to_f
  end
  len = (t = env[hdr_body_conf]) ? t[/\d+\z/].to_i : env_len
  headers[hdr_content_length] = (1024*len).to_s
  fn = format fn_format, len
  body = File.open fn
  [200, headers, body]
}
