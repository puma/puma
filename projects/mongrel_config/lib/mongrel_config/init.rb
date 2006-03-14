require 'rubygems'
require 'gem_plugin'
require 'mongrel'


class ConfigTool < GemPlugin::Plugin "/commands"
  include Mongrel::Command::Base

  def configure 
    if RUBY_PLATFORM =~ /mswin/
      options [
        ['-h', '--host ADDR', "Host to bind to for server", :@host, "0.0.0.0"],
        ['-p', '--port NUMBER', "Port to bind to", :@port, "3001"],
        ['-u', '--uri URI', "Where to put your config tool", :@uri, "/config"],
        ['-R', '--mongrel PATH', "Path to mongrel_rails_service", :@mongrel_script, "c:\\ruby\\bin\\mongrel_rails_service"]
      ]
    else
      options [ 
        ['-c', '--chdir PATH', "Change to dir before starting (will be expanded)", :@cwd, Dir.pwd],
        ['-P', '--pid FILE', "Where to write the PID", :@pid_file, "log/mongrel.pid"],
        ['-h', '--host ADDR', "Host to bind to for server", :@host, "0.0.0.0"],
        ['-p', '--port NUMBER', "Port to bind to", :@port, "3001"],
        ['-u', '--uri URI', "Where to put your config tool", :@uri, "/config"]
      ]
    end
  end
  
  def validate
      valid?(@uri, "Must give a uri")
      valid?(@port && @port.to_i > 0, "Must give a valid port")
      valid?(@host, "Host IP to bind must be given")
      
    if RUBY_PLATFORM !~ /mswin/    
      valid_dir? @cwd, "Cannot change to a directory that doesn't exist"
      Dir.chdir @cwd
      valid_dir? "log", "Log directory does not exist"
    end

    return @valid
  end


  def run
    # must require this here since rails and camping don't like eachother
    if RUBY_PLATFORM =~ /mswin/
      require 'mongrel_config/win32_app'
      $mongrel_rails_service = @mongrel_script
    else
      require 'mongrel_config/app'
    end

    resources = GemPlugin::Manager.instance.resource "mongrel_config", "/"
    $PID_FILE = @pid_file

    $server = Mongrel::Camping::start(@host,@port,@uri,Configure)

    puts "** Configure is running at http://#{@host}:#{@port}#{@uri}"
    if RUBY_PLATFORM !~ /mswin/
      trap("INT") { 
        $server.stop 
      }
      puts "Use CTRL-C to quit."
    else
      puts "Use CTRL-Pause/Break to quit."
    end

    # add our log directory
    $server.register("/log", Mongrel::DirHandler.new("log"))
    $server.register("/config/resources", Mongrel::DirHandler.new(resources))

    $server.acceptor.join
  end
end


