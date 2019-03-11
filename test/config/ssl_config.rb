key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__
ca = File.expand_path "../../examples/puma/client-certs/ca.crt", __FILE__

ssl_bind "0.0.0.0", 9292, :cert => cert, :key => key, :verify_mode => "peer", :ca => ca

app do |env|
  [200, {}, ["embedded app"]]
end

lowlevel_error_handler do |err|
  [200, {}, ["error page"]]
end
