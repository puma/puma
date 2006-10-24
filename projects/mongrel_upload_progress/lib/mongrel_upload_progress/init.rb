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
        last_checked_time = Mongrel::Uploads.last_checked(upload_id)
        return unless last_checked_time && Time.now - last_checked_time > @frequency
      end
      Mongrel::Uploads.send(action, upload_id, *args) 
      Mongrel::Uploads.update_checked_time(upload_id) unless action == :finish
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
    @counters[upid].last rescue nil
  end
  
  def last_checked(upid)
    @counters[upid].first rescue nil
  end

  def update_checked_time(upid)
    @guard.synchronize { @counters[upid][0] = Time.now }
  end

  def add(upid, size)
    @guard.synchronize do
      @counters[upid] = [Time.now, {:size => size, :received => 0}]
      puts "#{upid}: Added" if @debug
    end
  end

  def mark(upid, len)
    return unless status = check(upid)
    puts "#{upid}: Marking" if @debug
    @guard.synchronize { status[:received] = status[:size] - len }
  end

  def finish(upid)
    @guard.synchronize do
      puts "#{upid}: Finished" if @debug
      @counters.delete(upid)
    end
  end
  
  def list
    @counters.keys.sort
  end
end