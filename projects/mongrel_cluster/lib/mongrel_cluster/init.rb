require 'gem_plugin'
require 'mongrel'
require 'yaml'

module Cluster
  
  module ExecBase
     include Mongrel::Command::Base
      
      STATUS_OK = 0
      STATUS_MISSING = 2

      def validate
        valid_exists?(@config_file, "Configuration file does not exist. Run mongrel_rails cluster::configure.")
        return @valid
      end
      
      def read_options
        @options = { 
          "environment" => ENV['RAILS_ENV'] || "development",
          "port" => 3000,
          "pid_file" => "log/mongrel.pid",
          "servers" => 2 
        }
        conf = YAML.load_file(@config_file)
        @options.merge! conf if conf
        @pid_file = @options["pid_file"].split(".")
        
        start_port = end_port = @only
        start_port ||=  @options["port"].to_i
        end_port ||=  start_port + @options["servers"] - 1
        @ports = (start_port..end_port).to_a
  
      end

      def port_pid_file(port)
        "#{@pid_file[0]}.#{port}.#{@pid_file[1]}"
      end
      
      def start
        read_options
        
        argv = [ "mongrel_rails" ]
        argv << "start"
        argv << "-d"
        argv << "-e #{@options["environment"]}" if @options["environment"]
        argv << "-a #{@options["address"]}"  if @options["address"]
        argv << "-l #{@options["log_file"]}" if @options["log_file"]
        argv << "-c #{@options["cwd"]}" if @options["cwd"]
        argv << "-t #{@options["timeout"]}" if @options["timeout"]
        argv << "-m #{@options["mime_map"]}" if @options["mime_map"]
        argv << "-r #{@options["docroot"]}" if @options["docroot"]
        argv << "-n #{@options["num_procs"]}" if @options["num_procs"]
        argv << "-B" if @options["debug"]
        argv << "-S #{@options["config_script"]}" if @options["config_script"]
        argv << "--user #{@options["user"]}" if @options["user"]
        argv << "--group #{@options["group"]}" if @options["group"]
        argv << "--prefix #{@options["prefix"]}" if @options["prefix"]
        cmd = argv.join " "
        
        puts "Starting #{@ports.length} Mongrel servers..."

        @ports.each do |port|
          cmd += " -p #{port} -P #{port_pid_file(port)}"
          puts cmd if @verbose
          output = `#{cmd}`
          unless $?.success?
            puts cmd unless @verbose
            puts output
          end
        end
      end
      
      def stop
        read_options
      
        argv = [ "mongrel_rails" ]
        argv << "stop"
        argv << "-c #{@options["cwd"]}" if @options["cwd"]
        argv << "-f" if @force
        cmd = argv.join " "
        
        puts "Stopping #{@ports.length} Mongrel servers..."

        @ports.each do |port|
          cmd += " -P #{port_pid_file(port)}"
          puts cmd if @verbose
          output = `#{cmd}`
          unless $?.success?
            puts cmd unless @verbose
            puts output
          end
        end
      end

      def clean
        read_options

        puts "Cleaning #{@ports.length} pid files..."
        Dir.chdir @options["cwd"] if @options["cwd"]         
        
        @ports.each do |port|
          pid_file = port_pid_file(port)          
          puts "Removing {pid_file}!" if @verbose
          File.unlink(pid_file) if File.exists?(pid_file)
        end

      end
    
      def status
        read_options
        
        puts "Checking #{@ports.length} Mongrel servers..."
        Dir.chdir @options["cwd"] if @options["cwd"]

        status = STATUS_OK
        @ports.each do |port|
          pid_file = port_pid_file(port)
          if File.exists?(pid_file)
            pid = File.read(pid_file)
            ps_output = `ps -o cmd= -p #{pid}`
            status = STATUS_MISSING unless (ps_output =~ /mongrel_rails/) 
            msg = status == STATUS_OK ? "Found dog: #{port}" : "Lost dog: #{port}"           
          else
            msg = "Missing pid: #{pid_file}"
            status = STATUS_MISSING
          end
          puts msg
        end

        return status
      end
      
  end
  
  class Start < GemPlugin::Plugin "/commands"
    include ExecBase
    
    def configure
      options [ 
        ['-C', '--config PATH', "Path to cluster configuration file", :@config_file, "config/mongrel_cluster.yml"],
        ['-v', '--verbose', "Print all called commands and output.", :@verbose, false],
        ['', '--clean', "Remove pid_file before starting", :@clean, false],
        ['', '--only PORT', "Port number of cluster member", :@only, nil]
      ]
    end

    def run
      clean if @clean
      start      
    end
  end
  
  class Stop < GemPlugin::Plugin "/commands"
    include ExecBase

    def configure
      options [
       ['-C', '--config PATH', "Path to cluster configuration file", :@config_file, "config/mongrel_cluster.yml"],
       ['-f', '--force', "Force the shutdown.", :@force, false],
       ['-v', '--verbose', "Print all called commands and output.", :@verbose, false],
       ['', '--only PORT', "Port number of cluster member", :@only, nil]
      ]
    end
    
    def run
      stop
    end  
  end
  
  class Restart < GemPlugin::Plugin "/commands"
    include ExecBase

    def configure 
      options [ 
        ['-C', '--config PATH', "Path to cluster configuration file", :@config_file, "config/mongrel_cluster.yml"],
        ['-f', '--force', "Force the shutdown.", :@force, false],
        ['-v', '--verbose', "Print all called commands and output.", :@verbose, false],
        ['', '--only PORT', "Port number of cluster member", :@only, nil]       
      ]
    end
    
    def run
      stop
      start
    end
    
  end
  
  class Configure < GemPlugin::Plugin "/commands"
    include Mongrel::Command::Base
    
    def configure 
      options [
        ["-e", "--environment ENV", "Rails environment to run as", :@environment, nil],
        ['-p', '--port PORT', "Starting port to bind to", :@port, 3000],
        ['-a', '--address ADDR', "Address to bind to", :@address, nil],
        ['-l', '--log FILE', "Where to write log messages", :@log_file, nil],
        ['-P', '--pid FILE', "Where to write the PID", :@pid_file, "log/mongrel.pid"],
        ['-c', '--chdir PATH', "Change to dir before starting (will be expanded)", :@cwd, nil],
        ['-t', '--timeout SECONDS', "Timeout all requests after SECONDS time", :@timeout, nil],
        ['-m', '--mime PATH', "A YAML file that lists additional MIME types", :@mime_map, nil],
        ['-r', '--root PATH', "Set the document root (default 'public')", :@docroot, nil],
        ['-n', '--num-procs INT', "Number of processor threads to use", :@num_procs, nil],
        ['-B', '--debug', "Enable debugging mode", :@debug, nil],
        ['-S', '--script PATH', "Load the given file as an extra config script.", :@config_script, nil],
        ['-N', '--num-servers INT', "Number of Mongrel servers", :@servers, 2],
        ['-C', '--config PATH', "Path to cluster configuration file", :@config_file, "config/mongrel_cluster.yml"],
        ['', '--user USER', "User to run as", :@user, nil],
        ['', '--group GROUP', "Group to run as", :@group, nil],
        ['', '--prefix PREFIX', "Rails prefix to use", :@prefix, nil]
      ]
    end

    def validate
      @servers = @servers.to_i
      
      valid?(@servers > 0, "Must give a valid number of servers")
      valid_dir? File.dirname(@config_file), "Path to config file not valid: #{@config_file}"
      
      return @valid
    end

    def run
      @options = { 
        "port" => @port,
        "servers" => @servers,
        "pid_file" => @pid_file
      }
      
      @options["log_file"] = @log_file if @log_file
      @options["debug"] = @debug if @debug
      @options["num_procs"] = @num_procs if @num_procs
      @options["docroot"] = @docroot if @docroots
      @options["address"] = @address if @address
      @options["timeout"] = @timeout if @timeout
      @options["environment"] = @environment if @environment
      @options["mime_map"] = @mime_map if @mime_map
      @options["config_script"] = @config_script if @config_script
      @options["cwd"] = @cwd if @cwd
      @options["user"] = @user if @user
      @options["group"] = @group if @group
      @options["prefix"] = @prefix if @prefix
      
      puts "Writing configuration file to #{@config_file}."
      File.open(@config_file,"w") {|f| f.write(@options.to_yaml)}
    end  
  end

  class Status < GemPlugin::Plugin "/commands"
    include ExecBase

    def configure 
      options [ 
        ['-C', '--config PATH', "Path to cluster configuration file", :@config_file, "config/mongrel_cluster.yml"],
        ['-v', '--verbose', "Print all called commands and output.", :@verbose, false],
        ['', '--only PORT', "Port number of cluster member", :@only, nil]       
      ]
    end
    
    def run
      status
    end

  end
end

