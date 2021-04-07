require 'securerandom'

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : nil

long_header_hash = {}
long_header_hash['Content-Type'] = 'text; charset=utf-8'

25.times { |i| long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(25) }

run lambda { |env|
  # length = 1018  bytesize = 1024
  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (env['HTTP_LEN'] || env_len || 10).to_i

  body = Enumerator.new do |yielder|
    yielder <<  "#{Process.pid}\nHello World\n"
    len.times do |entry|
      yielder << str_1kb
    end
  end

  [200, long_header_hash.dup, body]
}
