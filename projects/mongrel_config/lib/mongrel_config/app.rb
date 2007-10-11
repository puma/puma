require 'erb'
require 'camping'
require 'mongrel/camping'


Camping.goes :Configure

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
      template.result(binding)
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
