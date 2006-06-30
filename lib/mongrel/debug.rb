
require 'logger'
require 'set'
require 'socket'

$mongrel_debugging=true

module MongrelDbg
  SETTINGS = { :tracing => {}}
  LOGGING = { }

  def MongrelDbg::configure(log_dir = "log/mongrel_debug")
    Dir.mkdir(log_dir) if not File.exist?(log_dir)
    @log_dir = log_dir
  end

  
  def MongrelDbg::trace(target, message)
    if SETTINGS[:tracing][target] and LOGGING[target]
      LOGGING[target].log(Logger::DEBUG, message)
    end
  end

  def MongrelDbg::begin_trace(target)
    SETTINGS[:tracing][target] = true
    if not LOGGING[target]
      LOGGING[target] = Logger.new(File.join(@log_dir, "#{target.to_s}.log"))
    end                          
    MongrelDbg::trace(target, "TRACING ON #{Time.now}")
  end

  def MongrelDbg::end_trace(target)
    SETTINGS[:tracing][target] = false
    MongrelDbg::trace(target, "TRACING OFF #{Time.now}")
    LOGGING[target].close
    LOGGING[target] = nil
  end

  def MongrelDbg::tracing?(target)
    SETTINGS[:tracing][target]
  end
end


module ObjectTracker
  @active_objects = nil

  def ObjectTracker.configure
    @active_objects = Set.new

    ObjectSpace.each_object do |obj|
      begin
        # believe it or not, some idiots actually alter the object_id method
        @active_objects << obj.object_id
      rescue Object
        # skip this one, he's an idiot
      end
    end
  end

  def ObjectTracker.sample
    ospace = Set.new
    counts = {}
    
    ObjectSpace.each_object do |obj|
      begin
        ospace << obj.object_id
        counts[obj.class] ||= 0
        counts[obj.class] += 1
      rescue Object
        # skip since object_id can magically get parameters
      end
    end
    
    dead_objects = @active_objects - ospace
    new_objects = ospace - @active_objects
    live_objects = ospace & @active_objects
    
    MongrelDbg::trace(:objects, "COUNTS: #{dead_objects.length},#{new_objects.length},#{live_objects.length}")
    
    if MongrelDbg::tracing? :objects
      top_20 = counts.sort{|a,b| b[1] <=> a[1]}[0..20]
      MongrelDbg::trace(:objects,"TOP 20: #{top_20.inspect}")
    end
    
    @active_objects = live_objects + new_objects
    
    [@active_objects, top_20]
  end

end

$open_files = {}

class IO
  alias_method :orig_open, :open
  alias_method :orig_close, :close

  def open(*arg, &blk)
    $open_files[self] = args.inspect
    orig_open(*arg,&blk)
  end

  def close(*arg,&blk)
    $open_files.delete self
    orig_close(*arg,&blk)
  end
end


module Kernel
  alias_method :orig_open, :open

  def open(*arg, &blk)
    $open_files[self] = arg[0]
    orig_open(*arg,&blk)
  end

  def log_open_files
    open_counts = {}
    $open_files.each do |f,args|
      open_counts[args] ||= 0
      open_counts[args] += 1
    end
    MongrelDbg::trace(:files, open_counts.to_yaml)
  end
end  



module RequestLog

  # Just logs whatever requests it gets to STDERR (which ends up in the mongrel
  # log when daemonized).
  class Access < GemPlugin::Plugin "/handlers"
    include Mongrel::HttpHandlerPlugin
    
    def process(request,response)
      p = request.params
      STDERR.puts "#{p['REMOTE_ADDR']} - [#{Time.now.httpdate}] \"#{p['REQUEST_METHOD']} #{p["REQUEST_URI"]} HTTP/1.1\""
    end
  end
  

  class Files < GemPlugin::Plugin "/handlers"
    include Mongrel::HttpHandlerPlugin
    
    def process(request, response)
      MongrelDbg::trace(:files, "#{Time.now} FILES OPEN BEFORE REQUEST #{request.params['PATH_INFO']}")
      log_open_files
    end
    
  end

  class Objects < GemPlugin::Plugin "/handlers"
    include Mongrel::HttpHandlerPlugin
    
    def process(request, response)
      MongrelDbg::trace(:objects, "#{'-' * 10}\n#{Time.now} OBJECT STATS BEFORE REQUEST #{request.params['PATH_INFO']}")
      ObjectTracker.sample
    end
    
  end
  

  class Params < GemPlugin::Plugin "/handlers"
    include Mongrel::HttpHandlerPlugin
    
    def process(request, response)
      MongrelDbg::trace(:rails, "#{Time.now} REQUEST #{request.params['PATH_INFO']}")
      MongrelDbg::trace(:rails, request.params.to_yaml)
    end

  end

  class Threads < GemPlugin::Plugin "/handlers"
    include Mongrel::HttpHandlerPlugin
    
    def process(request, response)
      MongrelDbg::trace(:threads, "#{Time.now} REQUEST #{request.params['PATH_INFO']}")
      ObjectSpace.each_object do |obj|
        begin
          if obj.class == Mongrel::HttpServer
            worker_list = obj.workers.list

            if worker_list.length > 0
              keys = "-----\n\tKEYS:"
              worker_list.each {|t| keys << "\n\t\t-- #{t}: #{t.keys.inspect}" }
            end

            MongrelDbg::trace(:threads, "#{obj.host}:#{obj.port} -- THREADS: #{worker_list.length} #{keys}")
          end
        rescue Object
          # ignore since obj.class can sometimes take parameters
        end
      end
    end
  end
end


END {
  MongrelDbg::trace(:files, "FILES OPEN AT EXIT")
  log_open_files
}
