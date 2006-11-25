require 'gem_plugin'
require 'mongrel'
require 'mongrel/rails'
require 'rbconfig'
require 'win32/service'
require 'fileutils'

module Service
  class Install < GemPlugin::Plugin "/commands"
    include Mongrel::Command::Base
  
    def configure
        options [
          ['-N', '--name SVC_NAME', "Required name for the service to be registered/installed.", :@svc_name, nil],
          ['-D', '--display SVC_DISPLAY', "Adjust the display name of the service.", :@svc_display, nil],
          ["-e", "--environment ENV", "Rails environment to run as", :@environment, ENV['RAILS_ENV'] || "development"],
          ['-p', '--port PORT', "Which port to bind to", :@port, 3000],
          ['-a', '--address ADDR', "Address to bind to", :@address, "0.0.0.0"],
          ['-l', '--log FILE', "Where to write log messages", :@log_file, "log/mongrel.log"],
          ['-P', '--pid FILE', "Where to write the PID", :@pid_file, "log/mongrel.pid"],
          ['-n', '--num-procs INT', "Number of processors active before clients denied", :@num_procs, 1024],
          ['-t', '--timeout TIME', "Timeout all requests after 100th seconds time", :@timeout, 0],
          ['-m', '--mime PATH', "A YAML file that lists additional MIME types", :@mime_map, nil],
          ['-c', '--chdir PATH', "Change to dir before starting (will be expanded)", :@cwd, Dir.pwd],
          ['-r', '--root PATH', "Set the document root (default 'public')", :@docroot, "public"],
          ['-B', '--debug', "Enable debugging mode", :@debug, false],
          ['-C', '--config PATH', "Use a config file", :@config_file, nil],
          ['-S', '--script PATH', "Load the given file as an extra config script.", :@config_script, nil],
          ['', '--prefix PATH', "URL prefix for Rails app", :@prefix, nil]
        ]
    end
    
    # When we validate the options, we need to make sure the --root is actually RAILS_ROOT
    # of the rails application we wanted to serve, because later "as service" no error 
    # show to trace this.
    def validate
      @cwd = File.expand_path(@cwd)
      valid_dir? @cwd, "Invalid path to change to: #@cwd"
  
      # change there to start, then we'll have to come back after daemonize
      Dir.chdir(@cwd)
  
      # start with the premise of app really exist.
      app_exist = true
      %w{app config log}.each do |path|
        if !File.directory?(File.join(@cwd, path))
          app_exist = false
          break
        end
      end

      valid?(@prefix[0].chr == "/" && @prefix[-1].chr != "/", "Prefix must begin with / and not end in /") if @prefix

      valid? app_exist == true, "The path you specified isn't a valid Rails application."

      valid_dir? File.dirname(@log_file), "Path to log file not valid: #@log_file"
      valid_dir? File.dirname(@pid_file), "Path to pid file not valid: #@pid_file"
      valid_dir? @docroot, "Path to docroot not valid: #@docroot"
      valid_exists? @mime_map, "MIME mapping file does not exist: #@mime_map" if @mime_map
      valid_exists? @config_file, "Config file not there: #@config_file" if @config_file

      # We should validate service existance here, right Zed?
      begin
        valid? !Win32::Service.exists?(@svc_name), "The service already exist, please remove it first."
      rescue
      end

      valid? @svc_name != nil, "A service name is mandatory."
      
      # default service display to service name
      @svc_display = @svc_name if !@svc_display

      return @valid
    end
    
    def run
      # check if mongrel_service.exe is in ruby bindir.
      gem_root = File.join(File.dirname(__FILE__), "..", "..")
      gem_executable = File.join(gem_root, "bin/mongrel_service.exe")
      bindir_executable = File.join(Config::CONFIG['bindir'], '/mongrel_service.exe')
      
      unless File.exist?(bindir_executable)
        STDERR.puts "** Copying native mongrel_service executable..."
        FileUtils.cp gem_executable, bindir_executable rescue nil
      end
      
      unless FileUtils.compare_file(bindir_executable, gem_executable)
        STDERR.puts "** Updating native mongrel_service executable..."
        FileUtils.rm_f bindir_executable rescue nil
        FileUtils.cp gem_executable, bindir_executable rescue nil
      end
      
      # build the command line
      argv = []
      
      # start using the native executable
      argv << '"' + bindir_executable + '"'
      
      # use the 'single' service for now
      argv << "single"
      
      # command line setting override config file settings
      @options = { :host => @address,  :port => @port, :cwd => @cwd,
        :log_file => @log_file, :pid_file => @pid_file, :environment => @environment,
        :docroot => @docroot, :mime_map => @mime_map,
        :debug => @debug, :includes => ["mongrel"], :config_script => @config_script,
        :num_procs => @num_procs, :timeout => @timeout, :cpu => @cpu, :prefix => @prefix
      }
      
      # if we are using a config file, pass -c and -C to the service instead of each start parameter.
      if @config_file
        STDERR.puts "** Using #{@config_file} instead of command line parameters."
        conf = YAML.load_file(@config_file)
        
        # add the root folder (-c)
        argv << "-c \"#{conf[:cwd]}\""
        
        # use the config file
        argv << "-C \"#{@config_file}\""

      else
        # use the command line instead
        # now the options
        argv << "-e #{@options[:environment]}" if @options[:environment]
        argv << "-p #{@options[:port]}"
        argv << "-a #{@options[:host]}"  if @options[:host]
        argv << "-l \"#{@options[:log_file]}\"" if @options[:log_file]
        argv << "-P \"#{@options[:pid_file]}\""
        argv << "-c \"#{@options[:cwd]}\"" if @options[:cwd]
        argv << "-t #{@options[:timeout]}" if @options[:timeout]
        argv << "-m \"#{@options[:mime_map]}\"" if @options[:mime_map]
        argv << "-r \"#{@options[:docroot]}\"" if @options[:docroot]
        argv << "-n #{@options[:num_procs]}" if @options[:num_procs]
        argv << "-B" if @options[:debug]
        argv << "-S \"#{@options[:config_script]}\"" if @options[:config_script]
        argv << "-u #{@options[:cpu.to_i]}" if @options[:cpu]
        argv << "--prefix \"#{@options[:prefix]}\"" if @options[:prefix]
      end

      svc = Win32::Service.new
      begin
        svc.create_service{ |s|
          s.service_name     = @svc_name
          s.display_name     = @svc_display
          s.binary_path_name = argv.join ' '
          s.dependencies     = []
          s.service_type     = Win32::Service::WIN32_OWN_PROCESS
        }
        puts "Mongrel service '#{@svc_display}' installed as '#{@svc_name}'."
      rescue Win32::ServiceError => err
        puts "There was a problem installing the service:"
        puts err
      end
      svc.close
    end
  end

  module ServiceValidation
    def configure
      options [
        ['-N', '--name SVC_NAME', "Required name for the service to be registered/installed.", :@svc_name, nil],
      ]
    end
    
    def validate
      valid? @svc_name != nil, "A service name is mandatory."
      
      # Validate that the service exists
      begin
        valid? Win32::Service.exists?(@svc_name), "There is no service with that name, cannot proceed."
        Win32::Service.open(@svc_name) do |svc|
          valid? svc.binary_path_name.include?("mongrel_service"), "The service specified isn't a Mongrel service."
        end
      rescue
      end
      
      return @valid
    end
  end
  
  class Remove < GemPlugin::Plugin "/commands"
    include Mongrel::Command::Base
    include ServiceValidation
    
    def run
      display_name = Win32::Service.getdisplayname(@svc_name)
      
      begin
        Win32::Service.stop(@svc_name)
      rescue
      end
      begin
        Win32::Service.delete(@svc_name)
      rescue
      end
      puts "#{display_name} service removed."
    end
  end
end
