Capistrano.configuration(:must_exist).load do
  set :mongrel_servers, 2
  set :mongrel_port, 8000
  set :mongrel_address, "127.0.0.1"
  set :mongrel_environment, "production"
  set :mongrel_conf, nil
  set :mongrel_user, nil
  set :mongrel_group, nil
  set :mongrel_prefix, nil
  
  desc <<-DESC
  Configure Mongrel processes on the app server. This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :configure_mongrel_cluster, :roles => :app do
    set_mongrel_conf
        
    argv = []
    argv << "mongrel_rails cluster::configure"
    argv << "-N #{mongrel_servers.to_s}"
    argv << "-p #{mongrel_port.to_s}"
    argv << "-e #{mongrel_environment}"
    argv << "-a #{mongrel_address}"
    argv << "-c #{current_path}"
    argv << "-C #{mongrel_conf}"
    argv << "--user #{mongrel_user}" if mongrel_user
    argv << "--group #{mongrel_group}" if mongrel_group
    argv << "--prefix #{mongrel_prefix}" if mongrel_prefix
    cmd = argv.join " "
    send(run_method, cmd)
  end
  
  desc <<-DESC
  Start Mongrel processes on the app server.  This uses the :use_sudo variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :start_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    send(run_method, "mongrel_rails cluster::start -C #{mongrel_conf}")
  end
  
  desc <<-DESC
  Restart the Mongrel processes on the app server by starting and stopping the cluster. This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is set to true.
  DESC
  task :restart_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    send(run_method, "mongrel_rails cluster::restart -C #{mongrel_conf}")
  end
  
  desc <<-DESC
  Stop the Mongrel processes on the app server.  This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :stop_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    send(run_method, "mongrel_rails cluster::stop -C #{mongrel_conf}")
  end
  
  desc <<-DESC
  Restart the Mongrel processes on the app server by calling restart_mongrel_cluster.
  DESC
  task :restart, :roles => :app do
    restart_mongrel_cluster
  end
  
  desc <<-DESC
  Start the Mongrel processes on the app server by calling start_mongrel_cluster.
  DESC
  task :spinner, :roles => :app do
    start_mongrel_cluster
  end
  
  def set_mongrel_conf
    set :mongrel_conf, "/etc/mongrel_cluster/#{application}.yml" unless mongrel_conf
  end

end