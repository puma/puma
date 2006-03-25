require 'logger'
require 'set'


$mongrel_debugging=true

module MongrelDbg
  SETTINGS = { :tracing => {}}
  LOGGING = { }

  def MongrelDbg::configure(log_dir = "mongrel_debug")
    Dir.mkdir(log_dir) if not File.exist?(log_dir)
    @log_dir = log_dir
  end

  
  def MongrelDbg::trace(target, message)
    if SETTINGS[:tracing][target]
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
end


module ObjectTracker
  @active_objects = nil
  @live_object_tracking = false

  def ObjectTracker.configure
    @active_objects = Set.new
    ObjectSpace.each_object do |obj|
      @active_objects << obj.object_id
    end
    srand @active_objects.object_id
    @sample_thread = Thread.new do
      loop do
        sleep(rand(3) + (rand(100)/100.0))
        ObjectTracker.sample
      end
    end
    @sample_thread.priority = 20
  end

  def ObjectTracker.start
    @stopit = true
    @live_object_tracking = true
    @stopit = false
  end

  def ObjectTracker.stop
    @live_object_tracking = false
  end

  def ObjectTracker.sample
    ospace = Set.new
    ObjectSpace.each_object do |obj|
      ospace << obj.object_id
    end
    
    dead_objects = @active_objects - ospace
    new_objects = ospace - @active_objects
    live_objects = ospace & @active_objects
    
    STDERR.puts "#{dead_objects.length},#{new_objects.length},#{live_objects.length}"

    @active_objects = live_objects + new_objects
  end

end

class Class
  alias_method :orig_new, :new
  
  @@count = 0
  @@stoppit = false
  @@class_caller_count = Hash.new{|hash,key| hash[key] = Hash.new(0)}
  
  def new(*arg,&blk)
    unless @@stoppit
      @@stoppit = true
      @@count += 1
      @@class_caller_count[self][caller[0]] += 1
      @@stoppit = false
    end
    orig_new(*arg,&blk)
  end


  def Class.report_object_creations
    @@stoppit = true
    puts "Number of objects created = #{@@count}"
    
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
    klass_list.each do |klass|
      puts "#{total[klass]}\t#{klass} objects created."
      caller_count = @@class_caller_count[ klass]
      caller_count.keys.sort_by{|call| -1*caller_count[call]}.each do |call|
        puts "\t#{call}\tCreated #{caller_count[call]} #{klass} objects."
      end
      puts
    end
  end

  def Class.reset_object_creations
    @@stopit = true
    @@count = 0
    @@class_caller_count = Hash.new{|hash,key| hash[key] = Hash.new(0)} 
    @@stoppit = false
  end
end


