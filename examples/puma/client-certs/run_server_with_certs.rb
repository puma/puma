require "bundler/setup"
require "puma"
require "puma/detect"
require "puma/puma_http11"
require "puma/minissl"

app = proc {|env|
  p env['puma.peercert']
  [200, {}, [ env['puma.peercert'] ]]
}
events = Puma::Events.new($stdout, $stderr)
server = Puma::Server.new(app, events)

context = Puma::MiniSSL::Context.new
context.key         = "certs/server.key"
context.cert        = "certs/server.crt"
context.ca          = "certs/ca.crt"
#context.verify_mode = Puma::MiniSSL::VERIFY_NONE
#context.verify_mode = Puma::MiniSSL::VERIFY_PEER
context.verify_mode = Puma::MiniSSL::VERIFY_PEER | Puma::MiniSSL::VERIFY_FAIL_IF_NO_PEER_CERT

server.add_ssl_listener("127.0.0.1", 4000, context)

server.run
sleep
#server.stop(true)
