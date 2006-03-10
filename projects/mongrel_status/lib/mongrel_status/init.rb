require 'mongrel'
require 'gem_plugin'

class Status < GemPlugin::Plugin "/commands"
  include Mongrel::Command::Base

  def configure 
    options [ 
             ['-c', '--chdir PATH', "Change to dir before starting (will be expanded)", :@cwd, Dir.pwd],
             ['-P', '--pid FILE', "Where to write the PID", :@pid_file, "log/mongrel.pid"]
    ]
  end
  
  def validate
    @cwd = File.expand_path(@cwd)
    valid_dir? @cwd, "Invalid path to change to during daemon mode: #@cwd"

    @pid_file = File.join(@cwd,@pid_file)
    valid_exists? @pid_file, "PID file #@pid_file does not exist. Not running?" 

    return @valid
  end


  def run
    pid = open(@pid_file) {|f| f.read }
    puts "Mongrel status:"
    puts "PID: #{pid}"
  end
end
