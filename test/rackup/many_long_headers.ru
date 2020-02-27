require 'securerandom'

long_header_hash = {}

30.times do |i|
  long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(1000)
end

run lambda { |env| [200, long_header_hash, ["Hello World"]] }
