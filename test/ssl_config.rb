key =  File.expand_path "../../examples/puma/puma_keypair.pem", __FILE__
cert = File.expand_path "../../examples/puma/cert_puma.pem", __FILE__

ssl_bind "0.0.0.0", 9292, :cert => cert, :key => key
