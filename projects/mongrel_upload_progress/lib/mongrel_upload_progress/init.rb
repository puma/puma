require 'mongrel'
require 'gem_plugin'

class Mongrel::Uploads
  include Singleton

  def initialize
    @guard = Mutex.new
    @counters = {}
  end

  def check(upid)
    @counters[upid]
  end

  def add(upid, size)
    stats = {'size' => size, 'received' => 0}
    @guard.synchronize do
      @counters[upid] = stats
    end
  end

  def mark(upid, len)
    upload = @counters[upid]
    recvd = upload['size'] - len
    @guard.synchronize do
      upload['received'] = recvd
    end
  end

  def finish(upid)
    upload = @counters[upid]
    recvd = upload['size']
    @guard.synchronize do
      upload['received'] = recvd
    end
  end
end

class Upload < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def initialize(options = {})
    @path_info      = options[:path_info]
    @request_notify = true
  end

  def request_begins(params)
    upload_notify(:add, params, params[Mongrel::Const::CONTENT_LENGTH].to_i) if params['PATH_INFO'] == @path_info
  end

  def request_progress(params, clen, total)
    upload_notify(:mark, params, clen) if params['PATH_INFO'] == @path_info
  end

  def process(request, response)
    upload_notify(:finish, request.params) if request.params['PATH_INFO'] == @path_info
  end

  private
  def upload_notify(action, params, *args)
    upload_id = Mongrel::HttpRequest.query_parse(params['QUERY_STRING'])['upload_id']
    if params[Mongrel::Const::REQUEST_METHOD] == 'POST' && upload_id
      Mongrel::Uploads.instance.send(action, upload_id, *args) if upload_id
    end
  end
end
