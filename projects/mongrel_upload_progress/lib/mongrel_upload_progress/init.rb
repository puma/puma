require 'mongrel'
require 'gem_plugin'
require File.join(File.dirname(__FILE__), 'progress')

class Uploads
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

class Progress < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def initialize(options)
  end

  def process(request, response)
    qs     = Mongrel::HttpRequest.query_parse(request.params['QUERY_STRING'])
    status = Mongrel::Uploads.instance.check(qs['upload_id'])
    response.start 200 do |head, out|
      out.write write_status(status, qs['upload_id'])
    end
  end

  protected
  def write_status(status, upload_id)
    status ? ([status['size'], status['received']] * ',') : "no status for #{upload_id}"
  end
end

class Upload < GemPlugin::Plugin "/handlers"
  include Mongrel::HttpHandlerPlugin

  def initialize(options = {})
    @upload_path  = options[:upload_path] || 'tmp/uploads'
    @redirect_url = options[:redirect_url]
    @request_notify = true
  end

  def request_begins(params)
    upload_notify(:add, params, params[Const::CONTENT_LENGTH].to_i)
  end

  def request_progress(params, clen, total)
    upload_notify(:mark, params, clen)
  end

  def process(request, response)
    upload_notify(:finish, request.params)
  end

  private
  def upload_notify(action, params, *args)
    upload_id = params['upload_id']
    if params[Const::REQUEST_METHOD] == 'POST' && upload_id
      Uploads.instance.send(action, upload_id, *args) if upload_id
    end
  end
end
