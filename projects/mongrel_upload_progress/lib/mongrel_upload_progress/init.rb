require 'mongrel'
require 'gem_plugin'

class Upload < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def initialize(options = {})
    @path_info      = options[:path_info]
    @frequency      = options[:frequency] || 3
    @request_notify = true
    if options[:drb]
      require 'drb'
      DRb.start_service
      Mongrel.const_set :Uploads, DRbObject.new(nil, options[:drb])
    else
      Mongrel.const_set :Uploads, Mongrel::UploadProgress.new
    end
    Mongrel::Uploads.debug = true if options[:debug]
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
      return unless params['PATH_INFO'] == @path_info &&
        params[Mongrel::Const::REQUEST_METHOD] == 'POST' &&
        upload_id = Mongrel::HttpRequest.query_parse(params['QUERY_STRING'])['upload_id']
      if action == :mark
        last_checked_time = instance_variable_get(checked_var(upload_id)) rescue nil
        return unless last_checked_time && Time.now - last_checked_time > @frequency
      end
      return unless Mongrel::Uploads.send(action, upload_id, *args)
      instance_variable_set(checked_var(upload_id), (action == :finish ? nil : Time.now))
    end

    def checked_var(key)
      key && "@checked_#{key}"
    end
end

# Keeps track of the status of all currently processing uploads
class Mongrel::UploadProgress
  attr_accessor :debug
  def initialize
    @guard    = Mutex.new
    @counters = {}
  end

  def check(upid)
    puts "#{upid}: Checking" if @debug
    instance_variable_get(upload_var(upid)) rescue nil
  end

  def add(upid, size)
    @guard.synchronize do
      @counters[upid] = Time.now
      instance_variable_set(upload_var(upid), {:size => size, :received => 0})
      puts "#{upid}: Added" if @debug
    end
    true
  rescue NameError # bad upid instance var
    puts $!.message
    @guard.synchronize { @counters[upid] = nil }
  end

  def mark(upid, len)
    puts "#{upid}: Marking" if @debug
    status = check(upid)
    status[:received] = status[:size] - len if status
  end

  def finish(upid)
    @guard.synchronize do
      puts "#{upid}: Finished" if @debug
      instance_variable_set(upload_var(upid),  nil) if @counters.delete(upid)
    end
    true
  end
  
  def list
    @counters.keys.sort
  end
  
  private
    def upload_var(key)
      key && "@upload_#{key}"
    end
end