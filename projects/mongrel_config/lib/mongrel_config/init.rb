require 'mongrel'
require 'gem_plugin'
require 'camping'


Camping.goes :Configure

module Configure::Models
end

module Configure::Controllers
  class Index < R '/'
    def get
      render :show
    end
  end

  class Start < R '/start'
    def get
      `mongrel_rails start -d -p 4000`
      redirect Index
    end
  end

  class Stop < R '/stop'
    def get
      `mongrel_rails stop`
      redirect Index
    end
  end

  class Shutdown < R '/shutdown'
    def get
      Thread.new do
        STDERR.puts "Shutdown requested..."
        sleep 2
        $server.stop
        STDERR.puts "Bye."
      end
      render :shutdown
    end
  end
end


module Configure::Views
  def layout
    html do
      head do
        title 'Mongrel Configure Tool'
      end
      body do
        h1 "Mongrel Configure Tool"

        p do
          a 'start',  :href => R(Start)
          a 'stop', :href => R(Stop)
          a 'shutdown', :href => R(Shutdown)
          a 'logs', :href => "../logs"
        end

        div.content do
          self << yield
        end
      end
    end
  end

  def show
    body do
      if _running?
        p { "Running..." }
      else
        p { "Not running..." }
      end
    end
  end

  def shutdown
    body do
      p { "Shutdown shortly..." }
    end
  end

  def _running?
    File.exist? $PID_FILE
  end
end

def Configure.create
  unless Configure::Models::Setting.table_exists?
    ActiveRecord::Schema.define(&Configure::Models.schema)
    Configure::Models::Setting.reset_column_information
  end
end


class ConfigTool < GemPlugin::Plugin "/commands"
  include Mongrel::Command::Base

  def configure 
    options [ 
             ['-c', '--chdir PATH', "Change to dir before starting (will be expanded)", :@cwd, Dir.pwd],
             ['-P', '--pid FILE', "Where to write the PID", :@pid_file, "log/mongrel.pid"],
             ['-h', '--host ADDR', "Host to bind to for server", :@host, "0.0.0.0"],
             ['-p', '--port NUMBER', "Port to bind to", :@port, "3001"],
             ['-u', '--uri URI', "Where to put your config tool", :@uri, "/config"]
    ]
  end
  
  def validate
    valid?(@uri, "Must give a uri")
    valid?(@port && @port.to_i > 0, "Must give a valid port")
    valid?(@host, "Host IP to bind must be given")

    valid_dir? @cwd, "Cannot change to a directory that doesn't exist"
    Dir.chdir @cwd
    valid_dir? "log", "Log directory does not exist"

    return @valid
  end


  def run
    require 'mongrel/camping'

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
    $server.register("/logs", Mongrel::DirHandler.new("log"))

    $server.acceptor.join
  end
end


