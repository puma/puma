require "bundler/setup"
require "puma"
require "puma/minissl"

case ARGV[0]

when "s"

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

when "g"

  def issue_cert(dn, key, serial, not_before, not_after, extensions, issuer, issuer_key, digest)
    cert = OpenSSL::X509::Certificate.new
    issuer = cert unless issuer
    issuer_key = key unless issuer_key
    cert.version = 2
    cert.serial = serial
    cert.subject = dn
    cert.issuer = issuer.subject
    cert.public_key = key.public_key
    cert.not_before = not_before
    cert.not_after = not_after
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer
    extensions.each {|oid, value, critical|
      cert.add_extension(ef.create_extension(oid, value, critical))
    }
    cert.sign(issuer_key, digest)
    cert
  end

  @ca_key  = OpenSSL::PKey::RSA.generate(2048)
  @svr_key = OpenSSL::PKey::RSA.generate(2048)
  @cli_key = OpenSSL::PKey::RSA.generate(2048)
  @ca  = OpenSSL::X509::Name.parse("/DC=net/DC=client-cbhq/CN=CA")
  @svr = OpenSSL::X509::Name.parse("/DC=net/DC=client-cbhq/CN=localhost")
  @cli = OpenSSL::X509::Name.parse("/DC=net/DC=client-cbhq/CN=localhost")
  now = Time.at(Time.now.to_i)
  ca_exts = [
    ["basicConstraints","CA:TRUE",true],
    ["keyUsage","cRLSign,keyCertSign",true],
  ]
  ee_exts = [
    #["keyUsage","keyEncipherment,digitalSignature",true],
    ["keyUsage","keyEncipherment,dataEncipherment,digitalSignature",true],
  ]
  @ca_cert  = issue_cert(@ca, @ca_key, 1, now, now+3600_000, ca_exts, nil, nil, OpenSSL::Digest::SHA1.new)
  @svr_cert = issue_cert(@svr, @svr_key, 2, now, now+1800_000, ee_exts, @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)
  @cli_cert = issue_cert(@cli, @cli_key, 3, now, now+1800_000, ee_exts, @ca_cert, @ca_key, OpenSSL::Digest::SHA1.new)

  File.open("ca.crt","wb") {|f| f.print @ca_cert.to_pem }
  File.open("ca.key","wb") {|f| f.print @ca_key.to_pem }
  File.open("server.crt","wb") {|f| f.print @svr_cert.to_pem }
  File.open("server.key","wb") {|f| f.print @svr_key.to_pem }
  File.open("client1.crt","wb") {|f| f.print @cli_cert.to_pem }
  File.open("client1.key","wb") {|f| f.print @cli_key.to_pem }
end
