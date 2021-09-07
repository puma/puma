require 'securerandom'

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : 10

ary_hdrs = []
25.times { |i| ary_hdrs << ["X-My-Header-#{i}", SecureRandom.hex(25)] }
ary_hdrs << ['Content-Type', 'text/plain; charset=utf-8']
ary_hdrs.freeze

run lambda { |env|
  body = "#{Process.pid}\nHello World\n".dup

  if (dly = env['HTTP_DLY'])
    sleep dly.to_f
    body << "Slept #{dly}\n"
  end

  # length = 1018  bytesize = 1024
  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (env['HTTP_LEN'] || env_len).to_i
  body << (str_1kb * len)
  headers = ary_hdrs.to_h
  headers['Content-Length'] = body.bytesize.to_s
  [200, headers, [body]]
}
