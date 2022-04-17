require "localhost"

ssl_bind "0.0.0.0", 9292

app do |env|
  [200, {}, ["self-signed certificate app"]]
end
