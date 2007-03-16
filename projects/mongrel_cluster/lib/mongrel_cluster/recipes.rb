Capistrano.configuration(:must_exist).load do
  set :mongrel_servers, 2
  set :mongrel_port, 8000
  set :mongrel_address, "127.0.0.1"
  set :mongrel_environment, "production"
  set :mongrel_conf, nil
  set :mongrel_user, nil
  set :mongrel_group, nil
  set :mongrel_prefix, nil
  set :mongrel_rails, 'mongrel_rails'
  set :mongrel_clean, false
  set :mongrel_pid_file, nil
  set :mongrel_log_file, nil
  set :mongrel_config_script, nil
 
  desc <<-DESC
  Configure Mongrel processes on the app server. This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :configure_mongrel_cluster, :roles => :app do
    set_mongrel_conf
        
    argv = []
    argv << "#{mongrel_rails} cluster::configure"
    argv << "-N #{mongrel_servers.to_s}"
    argv << "-p #{mongrel_port.to_s}"
    argv << "-e #{mongrel_environment}"
    argv << "-a #{mongrel_address}"
    argv << "-c #{current_path}"
    argv << "-C #{mongrel_conf}"
    argv << "-P #{mongrel_pid_file}" if mongrel_pid_file
    argv << "-l #{mongrel_log_file}" if mongrel_log_file
    argv << "--user #{mongrel_user}" if mongrel_user
    argv << "--group #{mongrel_group}" if mongrel_group
    argv << "--prefix #{mongrel_prefix}" if mongrel_prefix
    argv << "-S #{mongrel_config_script}" if mongrel_config_script
    cmd = argv.join " "
    send(run_method, cmd)
  end
  
  desc <<-DESC
  Start Mongrel processes on the app server.  This uses the :use_sudo variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :start_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    cmd = "#{mongrel_rails} cluster::start -C #{mongrel_conf}"
    cmd += " --clean" if mongrel_clean    
    send(run_method, cmd)
  end
  
  desc <<-DESC
  Restart the Mongrel processes on the app server by starting and stopping the cluster. This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is set to true.
  DESC
  task :restart_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    cmd = "#{mongrel_rails} cluster::restart -C #{mongrel_conf}"
    cmd += " --clean" if mongrel_clean    
    send(run_method, cmd)
  end
  
  desc <<-DESC
  Stop the Mongrel processes on the app server.  This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :stop_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    cmd = "#{mongrel_rails} cluster::stop -C #{mongrel_conf}"
    cmd += " --clean" if mongrel_clean    
    send(run_method, cmd)
  end

  desc <<-DESC
  Check the status of the Mongrel processes on the app server.  This uses the :use_sudo
  variable to determine whether to use sudo or not. By default, :use_sudo is
  set to true.
  DESC
  task :status_mongrel_cluster , :roles => :app do
    set_mongrel_conf
    send(run_method, "#{mongrel_rails} cluster::status -C #{mongrel_conf}")
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
