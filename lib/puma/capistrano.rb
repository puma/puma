puts 1
Capistrano::Configuration.instance.load do
  after "deploy:stop", "puma:stop"
  after "deploy:start", "puma:start"
  after "deploy:restart", "puma:restart"

  _cset(:puma_role)      { :app }

  namespace :puma do
    desc "Start puma"
    task :start, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      puma_env = fetch(:stage, "production")
      run "cd #{current_path} && #{fetch(:bundle_cmd, "bundle")} exec puma -d -e #{puma_env} -b 'unix://#{shared_path}/sockets/puma.sock' -S #{shared_path}/sockets/puma.state --control 'unix://#{shared_path}/sockets/pumactl.sock' >> #{shared_path}/log/puma-#{stage}.log 2>&1", :pty => false
    end

    desc "Stop puma"
    task :stop, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{fetch(:bundle_cmd, "bundle")} exec pumactl -S #{shared_path}/sockets/puma.state stop"
    end

    desc "Restart puma"
    task :restart, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{fetch(:bundle_cmd, "bundle")} exec pumactl -S #{shared_path}/sockets/puma.state restart"
    end

  end
end