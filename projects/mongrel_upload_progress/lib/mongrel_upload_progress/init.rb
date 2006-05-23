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
    if params[Const::REQUEST_METHOD] == 'POST'
      qs = self.class.query_parse(params['QUERY_STRING'])
      if qs['upload_id'] and not qs['upload_id'].empty?
        upload_id = qs['upload_id']
        Uploads.instance.add(upload_id, clen) if upload_id
      end
    end

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
  end

  def process(request, response)
    @cgi   = nil
    @files = []
    qs   = Mongrel::HttpRequest.query_parse(request.params['QUERY_STRING'])
    if request.params[Mongrel::Const::REQUEST_METHOD] == 'POST' && qs['upload_id']
      save_file(request, response, qs['upload_id'])
      process_upload(request, response, qs['upload_id'])
    else
      response.start(204) {}
    end
  end

  protected
  # Called when a file has been uploaded.
  def process_upload(request, response, upid)
    if @redirect_url
      response.start 302 do |head, out|
        location = '%s%supload_id=%s' % [@redirect_url, (@redirect_url =~ /\?/ ? '&' : '?'), upid]
        head['Location'] = @files.inject(location) { |loc, file| loc << "&file[]=#{file}" }
      end
    else
      response.start(200) { |h, o| o.write "Successfully uploaded #{@files * ', '}."}
    end
  end

  def save_file(request, response, upid)
    @cgi         = Mongrel::CGIWrapper.new(request, response)
    @cgi.handler = self

    @cgi.params['data'].each_with_index do |data, i|
      @files << data.original_filename
      upload_file = File.join(@upload_path, [upid, i, @files.last] * '.')
      FileUtils.mkdir_p(@upload_path)
      if data.is_a?(Tempfile)
        FileUtils.cp data.path, upload_file
      else
        File.open(upload_file, 'wb') { |f| f.write data.read }
      end
    end
  end
end
