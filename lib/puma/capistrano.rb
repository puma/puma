Capistrano::Configuration.instance.load do
  after 'deploy:stop', 'puma:stop'
  after 'deploy:start', 'puma:start'
  after 'deploy:restart', 'puma:restart'

  # Ensure the tmp/sockets directory is created by the deploy:setup task and
  # symlinked in by the deploy:update task. This is not handled by Capistrano
  # v2 but is fixed in v3.
  shared_children.push('tmp/sockets')

  _cset(:puma_cmd)    { "#{fetch(:bundle_cmd, 'bundle')} exec puma" }
  _cset(:pumactl_cmd) { "#{fetch(:bundle_cmd, 'bundle')} exec pumactl" }
  _cset(:puma_env)    { fetch(:rack_env, fetch(:rails_env, 'production')) }
  _cset(:puma_state)  { "#{shared_path}/sockets/puma.state" }
  _cset(:puma_socket) { "unix://#{shared_path}/sockets/puma.sock" }
  _cset(:puma_role)   { :app }

  namespace :puma do
    desc 'Start puma'
    task :start, :roles => lambda { puma_role }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{puma_cmd} #{start_options}", :pty => false
    end

    desc 'Stop puma'
    task :stop, :roles => lambda { puma_role }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{pumactl_cmd} -S #{state_path} stop"
    end

    desc 'Restart puma'
    task :restart, :roles => lambda { puma_role }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{pumactl_cmd} -S #{state_path} restart"
    end

    desc 'Restart puma (phased restart)'
    task :phased_restart, :roles => lambda { puma_role }, :on_no_matching_servers => :continue do
      run "cd #{current_path} && #{pumactl_cmd} -S #{state_path} phased-restart"
    end

  end

  def start_options
    if config_file
      "-q -d -e #{puma_env} -C #{config_file}"
    else
      "-q -d -e #{puma_env} -b '#{puma_socket}' -S #{state_path} --control 'unix://#{shared_path}/sockets/pumactl.sock'"
    end
  end

  def config_file
    @_config_file ||= begin
      file = fetch(:puma_config_file, nil)
      file = "./config/puma/#{puma_env}.rb" if !file && File.exists?("./config/puma/#{puma_env}.rb")
      file
    end
  end

  def puma_env
    fetch(:rack_env, fetch(:rails_env, 'production'))
  end

  def state_path
    (config_file ? configuration.options[:state] : nil) || puma_state
  end

  def configuration
    require 'puma/configuration'

    config = Puma::Configuration.new(:config_file => config_file)
    config.load
    config
  end
end
