Capistrano::Configuration.instance.load do
  after 'deploy:stop', 'puma:stop'
  after 'deploy:start', 'puma:start'
  after 'deploy:restart', 'puma:restart'

  # Ensure the tmp/sockets directory is created by the deploy:setup task and
  # symlinked in by the deploy:update task. This is not handled by Capistrano
  # v2 but is fixed in v3.
  shared_children.push('tmp/sockets')

  _cset(:puma_cmd) { "#{fetch(:bundle_cmd, 'bundle')} exec puma" }
  _cset(:pumactl_cmd) { "#{fetch(:bundle_cmd, 'bundle')} exec pumactl" }
  _cset(:puma_state) { "#{shared_path}/sockets/puma.state" }
  _cset(:puma_role) { :app }

  namespace :puma do
    desc 'Start puma'
    task :start, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      puma_env = fetch(:rack_env, fetch(:rails_env, 'production'))
      run "cd #{current_path} && #{fetch(:puma_cmd)} -q -d -e #{puma_env} -b 'unix://#{shared_path}/sockets/puma.sock' -S #{fetch(:puma_state)} --control 'unix://#{shared_path}/sockets/pumactl.sock'", :pty => false
    end

    desc 'Stop puma'
    task :stop, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{fetch(:pumactl_cmd)} -S #{fetch(:puma_state)} stop"
    end

    desc 'Restart puma'
    task :restart, :roles => lambda { fetch(:puma_role) }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{fetch(:pumactl_cmd)} -S #{fetch(:puma_state)} restart"
    end
  end
end
