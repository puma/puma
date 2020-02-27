require 'securerandom'

long_header_hash = {}

25.times do |i|
  long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(25)
end

response = SecureRandom.hex(100_000) # A 100kb document

run lambda { |env| [200, long_header_hash.dup, [response.dup]] }
