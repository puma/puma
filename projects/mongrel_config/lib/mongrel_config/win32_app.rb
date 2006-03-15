require 'erb'
require 'camping'
require 'mongrel/camping'
require 'yaml'
require 'thread'

Camping.goes :Configure

require 'mongrel_config/win32'

$service_group = ThreadGroup.new
$service_logs = ""

module Configure
  module Controllers
    class Index < R '/'
      def get
        @services = W32Support.list
        render :list
      end
    end
    
    class Info < R '/info/(\w+)'
      def get(name)
        @services = W32Support.list.select {|s| s.service_name == name }
        render :info
      end
    end
    
    class Start < R '/start/(\w+)'
      def get(service)
        runner = Thread.new do
          W32Support.start(service) do |status|
            $service_logs << "Starting #{service}: #{status}\n"
            sleep 1
          end
        end

        $service_group.add(runner)

        redirect Index
      end
    end    
    
    class Stop < R '/stop/(\w+)'
      def get(service)
        runner = Thread.new do
          W32Support.stop(service) do |status|
            $service_logs << "Starting #{service}: #{status}\n"
            sleep 1
          end
        end

        $service_group.add(runner)
        redirect Index
      end
    end
    
    # eventually this will also let you see a particular service's logs
    class Logs < R '/logs'
      def get
        render :service_logs
      end
    end

    class ClearLogs < R '/clear_logs'
      def get
        $service_logs = ""
        $service_logs << "#{Time.now}: CLEARED"

        redirect Logs
      end
    end

    class Install < R '/install'
      def get
        render :install_form
      end

      def post
        options = []
        if bad?(input.service_name) or bad?(input.root) or bad?(input.environment) or bad?(input.address) or bad?(input.port)
          @result = "ERROR: You must fill out all mandatory (*) fields."
          render :install_result
        else
          options << ["-n", input.service_name]
          options << ["-r", '"' + input.root + '"']
          options << ["-e", input.environment]
          options << ["-b", input.address]
          options << ["-p", input.port]
          options << ["-d", input.display_name] if good? input.display_name
          options << ["-m", '"' + input.mime + '"'] if good? input.mime
          options << ["-P", input.num_procs] if good? input.num_procs
          options << ["-t", input.timeout] if good? input.timeout
          options << ["-c", input.cpu] if good? input.cpu
          
          begin
            @result = `ruby #$mongrel_rails_service install #{options.join(' ')}`
            $service_logs << @result
          rescue
            @result = "Failed to start #{input.service_name}: #$!"
            $service_logs << @result
          end
          
          render :install_result
        end
      end

      def good?(field)
        field and not field.strip.empty?
      end
      
      def bad?(field)
        not good? field
      end
    end


    class Delete < R '/delete/(\w+)'
      def get(name)
        W32Support.delete(name)
        $service_logs << "Deleted #{name}\n"
        redirect Index
      end
    end
  end
  
  
  module Views
    def layout
      links = [ 
        ["/config", "Status"], 
        ["/config/install", "Install"], 
        ["/config/logs", "Logs"]
        ]
      body_content = yield
      currently_running = _running_procs

      open(GemPlugin::Manager.instance.resource("mongrel_config", "/index_win32.html")) do |f|
        template = ERB.new(f.read)
        self << template.result(binding)
      end
    end
    

    def list
      div :id=>"viewport" do
        table do
          tr { th { "Service"}; th { "Status"}; th { "Control" }; th { "Delete" } }
          @services.each do |s|
            status = W32Support.status(s.service_name)
            tr { 
              td { a(s.service_name, :href => "/info/#{s.service_name}") }
              td { status.capitalize }
              td { 
                if status =~ /stopped/
                  a("start",:href => "/start/#{s.service_name}")
                elsif status =~ /running/
                  a("stop",:href => "/stop/#{s.service_name}") 
                else
                  b { "in progress" }
                end
              }
              td {
                a("delete!",:href => "/delete/#{s.service_name}", 
                  :onclick=>"return confirm('Delete #{s.service_name}?') == '1'")
              }
            }
          end
        end
      end
    end
    

    def info
      div :id=>"viewport" do
        @services.each do |s|
        
          h2 { "#{s.service_name} service information" }
          table do
            tr { th {"Attribute"}; th {"Value"} }
            
            s.each_pair do |memb,obj|
              name = memb.to_s.tr("_"," ").capitalize
              tr { 
                td { b { "#{name}: " } }
                td { obj.inspect }
              }
            end
          end
        end
      end
    end

    def service_logs
      h2 { "Latest Service Activity Logs" }
      a("[clear logs]", :href => "/clear_logs")

      div :id=>"viewport" do
        pre :style=>"font-size: 10pt;" do
          self << $service_logs
        end
      end
    end

    def install_form
      div do
        h2 { "Install New Mongrel Service" }
        p { "Items with an * are mandatory.  Leave an item blank to not specify it." }
        form :action=>"/install", :method=>"POST" do
          b { "* Service Name: "}; input :name => "service_name"; br
          b { "* Root: "}; input :name => "root"; br
          b { "* Environment: "}; input :name => "environment", :value => "development"; br
          b { "*Address: "}; input :name => "address", :value => "0.0.0.0"; br
          b { "*Port: "}; input :name => "port", :value => "4000", :size => 6; br
          b { "Display Name: "}; input :name => "display_name"; br
          b { "MIME Map File: "};  input :name => "mime"; br
          b { "Number Processor Threads: "}; input :name => "num_procs", :size => 3; br
          b { "Request Timeout: "}; input :name => "timeout", :size => 3; br
          b { "Assigned CPU: " }; input :name => "cpu", :size => 2; br

          p { input :type=>"submit", :value => "INSTALL" }
        end
      end
    end


    def install_result
      div :id=>"viewport" do
        h2 { "Install Results"}
        pre do
          self << @result
        end
      end
    end

    def _running_procs
      running = []
      W32Support.list.each {|s| running << s.service_name if s.current_state =~ /running/}
      running
    end
    
  end
end







