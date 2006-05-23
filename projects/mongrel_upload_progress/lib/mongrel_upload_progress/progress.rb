module Mongrel
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
  
  class HttpRequest
    def initialize(params, initial_body, socket)
      @params = params
      @socket = socket

      clen = params[Const::CONTENT_LENGTH].to_i - initial_body.length
      upload_id = nil
      
      if params[Const::REQUEST_METHOD] == 'POST'
        qs = self.class.query_parse(params['QUERY_STRING'])
        if qs['upload_id'] and not qs['upload_id'].empty?
          upload_id = qs['upload_id']
          Uploads.instance.add(upload_id, clen) if upload_id
        end
      end

      if clen > Const::MAX_BODY
        @body = Tempfile.new(self.class.name)
        @body.binmode
      else
        @body = StringIO.new
      end

      begin
        @body.write(initial_body)

        # write the odd sized chunk first
        clen -= @body.write(@socket.read(clen % Const::CHUNK_SIZE))
        
        # then stream out nothing but perfectly sized chunks
        while clen > 0
          data = @socket.read(Const::CHUNK_SIZE)
          # have to do it this way since @socket.eof? causes it to block
          raise "Socket closed or read failure" if not data or data.length != Const::CHUNK_SIZE
          clen -= @body.write(data)
          Uploads.instance.mark(upload_id, clen) if upload_id
        end

        # rewind to keep the world happy
        Uploads.instance.finish(upload_id) if upload_id
        @body.rewind
      rescue Object
        # any errors means we should delete the file, including if the file is dumped
        STDERR.puts "Error reading request: #$!"
        @body.delete if @body.class == Tempfile
        @body = nil # signals that there was a problem
      end
    end
  end
end