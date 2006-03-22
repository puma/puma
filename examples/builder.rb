require 'mongrel'

config = Mongrel::Configurator.new :host => "127.0.0.1" do
  load_plugins :includes => ["mongrel"], :excludes => ["rails"]
  daemonize :cwd => Dir.pwd, :log_file => "mongrel.log", :pid_file => "mongrel.pid"
  
  listener :port => 3000 do
    uri "/app", :handler => Mongrel::DirHandler.new(".", load_mime_map("mime.yaml"))
    load_plugins :includes => ["mongrel", "rails"]
  end

  trap("INT") { stop }
  run
end

config.join


