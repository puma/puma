require 'mongrel'
require 'gem_plugin'
require 'camping'
require 'erb'

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
      render :start
    end

    def post
      @results = `mongrel_rails start -d -p #{input.port} -e #{input.env} -n #{input.num_procs} -a #{input.address}`
      render :start_done
    end
  end

  class Kill < R '/kill/(\w+)'

    def get(signal)
      if _running?
        @signal = signal.upcase
        pid = open($PID_FILE) {|f| f.read }
        begin
          Process.kill(@signal, pid.to_i)
          @results = "Mongrel sent PID #{pid} signal #{@signal}."
        rescue
          puts "ERROR: #$!"
          @results = "Failed to signal the Mongrel process.  Maybe it is not running?<p>#$!</p>"
        end
      else
        @results = "Mongrel does not seem to be running.  Maybe delete the pid file #{$PID_FILE} or start again."
      end
      
      render :kill
    end
  end


  class Stop < R '/stop'
    def get
      render :stop
    end
  end

  class Logs < R '/logs'
    def get
      @log_files = Dir.glob("log/**/*")
      render :logs
    end
  end

end


module Configure::Views
  def layout
    body_content = yield
    currently_running = _running?
    pid = _pid 
    open(GemPlugin::Manager.instance.resource("mongrel_config", "/index.html")) do |f|
      template = ERB.new(f.read)
      self << template.result(binding)
    end
  end

  def show
    div do
      h2 { "Status" }
      if _running?
        p { "Currently running with PID #{_pid}." }
      else
        p { "Mongrel is not running." }
      end
    end
  end

  def start
    div do
      form :action => "/start", :method => "POST" do
        p { span { "Port:" }; input :name => "port", :value => "4000" }
        p { span { "Environment:" }; input :name => "env", :value => "development" }
        p { span { "Address:" }; input :name => "address", :value => "0.0.0.0" }
        p { span { "Number Processors:" }; input :name => "num_procs", :value => "20" }
        input :type => "submit", :value => "START"
      end
    end
  end

  def start_done
    div do
      p { @results }
    end
  end

  def kill
    div do
      p { @results }
      
      case @signal
        when "HUP":
          p { "A reload (HUP) does not stop the process, but may not be complete." }
        when "TERM":
          p { "Stopped with TERM signal.  The process should exit shortly, but only after processing pending requests." }
        when "USR2":
          p { "Complete restart (USR2) may take a little while.  Check status in a few seconds or read logs." }
        when "KILL":
          p { "Process was violently stopped (KILL) so pending requests will be lost." }
        end
    end
  end

  def stop
    if _running?
      ul do
        li { a "Stop (TERM)", :href => "/kill/term" }
        li { a "Reload (HUP)", :href => "/kill/hup" }
        li { a "Restart (USR2)", :href => "/kill/usr2" }
        li { a "Kill (KILL)", :href => "/kill/kill" }
      end
    else
      p { "Mongrel does not appear to be running (no PID file at #$PID_FILE)." }
    end
  end

  def logs
    div do
      h2 { "Logs" }
      table do
        tr do
          th { "File"}; th { "Bytes" }; th { "Last Modified" }
        end
        @log_files.each do |file|
          tr do
            td { a file, :href => "../#{file}" }
            td { File.size file }
            td { File.mtime file }
          end
        end
      end
    end
  end
  
  def _running?
    File.exist? $PID_FILE
  end

  def _pid
    open($PID_FILE) {|f| f.read } if _running?
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
    $server.register("/log", Mongrel::DirHandler.new("log"))
    resources = GemPlugin::Manager.instance.resource "mongrel_config", "/"
    $server.register("/config/resources", Mongrel::DirHandler.new(resources))

    $server.acceptor.join
  end
end


