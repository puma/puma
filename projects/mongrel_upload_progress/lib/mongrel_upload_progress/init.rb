require 'mongrel'
require 'gem_plugin'

class Upload < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def initialize(options = {})
    @path_info      = options[:path_info]
    @request_notify = true
    if options[:drb]
      require 'drb'
      DRb.start_service
      Mongrel.const_set :UploadStatus, DRbObject.new(nil, options[:drb])
    else
      Mongrel.const_set :UploadStatus, Mongrel::UploadProgress.new
    end
    Mongrel::Upload::Status.instance.instance_variable_set(:@debug, true) if options[:debug]
  end

  def request_begins(params)
    upload_notify(:add, params, params[Mongrel::Const::CONTENT_LENGTH].to_i)
  end

  def request_progress(params, clen, total)
    upload_notify(:mark, params, clen)
  end

  def process(request, response)
    upload_notify(:finish, request.params)
  end

  private
    def upload_notify(action, params, *args)
      return unless params['PATH_INFO'] == @path_info && params[Mongrel::Const::REQUEST_METHOD] == 'POST'
      upload_id = Mongrel::HttpRequest.query_parse(params['QUERY_STRING'])['upload_id']
      Mongrel::UploadStatus.send(action, upload_id, *args) if upload_id
    end
end

# Keeps track of the status of all currently processing uploads
class Mongrel::UploadProgress
  def initialize
    @guard    = Mutex.new
    @counters = {}
  end

  def check(upid)
    status = @counters[upid]
    puts "#{upid}: Checking" if @debug
    instance_variable_get(upload_var(status)) if status
  end
  
  def last_checked(upid)
    status = @counters[upid]
    instance_variable_get(checked_var(status)) if status
  end

  def add(upid, size)
    @guard.synchronize do
      @counters[upid] = rand(Time.now.to_i).to_s.intern
      instance_variable_set(upload_var(@counters[upid]), {:size => size, :received => 0})
      puts "#{upid}: Added" if @debug
    end
  end

  def mark(upid, len)
    last_checked_time = last_checked(upid)
    if last_checked_time.nil? || Time.now-last_checked_time > 3
      status = check(upid)
      status[:received] = status[:size] - len
      instance_variable_set(checked_var(@counters[upid]), Time.now)
      puts "#{upid}: #{status[:received]}" if @debug
    end
  end

  def finish(upid)
    @guard.synchronize do
      puts "#{upid}: Finished" if @debug
      counter = @counters.delete(upid)
      return unless counter
      instance_variable_set(upload_var(counter),  nil)
      instance_variable_set(checked_var(counter), nil)
    end
    true
  end
  
  def list
    @counters.keys.sort
  end
  
  private
    def upload_var(key)
      "@upload_#{key}"
    end
    
    def checked_var(key)
      "@checked_#{key}"
    end
end