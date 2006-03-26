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
  @live_object_tracking = true

  def ObjectTracker.configure
    @active_objects = Set.new

    ObjectSpace.each_object do |obj|
      @active_objects << obj.object_id
    end
  end


  def ObjectTracker.start
    @live_object_tracking = true
  end

  def ObjectTracker.stop
    @live_object_tracking = false
  end

  def ObjectTracker.sample
    Class.stopit do
      ospace = Set.new
      counts = {}
      
      # Strings can't be tracked easily and are so numerous that they drown out all else
      # so we just ignore them in the counts.
      ObjectSpace.each_object do |obj|
        if not obj.kind_of? String
          ospace << obj.object_id
          counts[obj.class] ||= 0
          counts[obj.class] += 1
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
    Class.stopit do
      open_counts = {}
      $open_files.each do |f,args|
        open_counts[args] ||= 0
        open_counts[args] += 1
      end
      MongrelDbg::trace(:files, open_counts.to_yaml)
    end
  end
end  



class Class
  alias_method :orig_new, :new
  
  @@count = 0
  @@stopit = false
  @@class_caller_count = Hash.new{|hash,key| hash[key] = Hash.new(0)}
  
  def new(*arg,&blk)
    unless @@stopit
      @@stopit = true
      @@count += 1
      @@class_caller_count[self][caller.join("\n\t")] += 1
      @@stopit = false
    end
    orig_new(*arg,&blk)
  end


  def Class.report_object_creations(out=$stderr, more_than=20)
    Class.stopit do
      out.puts "Number of objects created = #{@@count}"
      
      total = Hash.new(0)
      
      @@class_caller_count.each_key do |klass|
        caller_count = @@class_caller_count[klass]
        caller_count.each_value do |count|
          total[klass] += count
        end
      end
      
      klass_list = total.keys.sort{|klass_a, klass_b| 
        a = total[klass_a]
        b = total[klass_b]
        if a != b
          -1* (a <=> b)
        else
          klass_a.to_s <=> klass_b.to_s
        end
      }

      below_count = 0

      klass_list.each do |klass|
        below_calls = 0
        if total[klass] > more_than
          out.puts "#{total[klass]}\t#{klass} objects created."
          caller_count = @@class_caller_count[ klass]
          caller_count.keys.sort_by{|call| -1*caller_count[call]}.each do |call|
            if caller_count[call] > more_than
              out.puts "\t** #{caller_count[call]} #{klass} objects AT:"
              out.puts "\t#{call}\n\n"
            else
              below_calls += 1
            end
          end
          out.puts "\t#{below_calls} more objects had calls less that #{more_than} limit.\n\n" if below_calls > 0
        else
          below_count += 1
        end
      end

      out.puts "\t** #{below_count} More objects were created but the count was below the #{more_than} limit." if below_count > 0
    end
  end

  def Class.reset_object_creations
    Class.stopit do
      @@count = 0
      @@class_caller_count = Hash.new{|hash,key| hash[key] = Hash.new(0)} 
    end
  end

  def Class.stopit
    @@stopit = true
    yield
    @@stopit = false
  end

end


module RequestLog
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
      MongrelDbg::trace(:objects, "#{Time.now} OBJECT STATS BEFORE REQUEST #{request.params['PATH_INFO']}")
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
end


END {
open("log/mongrel_debug/object_tracking.log", "w") {|f| Class.report_object_creations(f) }
MongrelDbg::trace(:files, "FILES OPEN AT EXIT")
log_open_files
}
