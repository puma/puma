module Puma
  class UnixBinding < Binding
    def initialize(uri)
      super
      @path = "#{uri.host}#{uri.path}".gsub("%20", " ")
      umask = nil
      mode = nil
      backlog = 1024

      if uri.query
        params = Util.parse_query uri.query
        if u = params['umask']
          # Use Integer() to respect the 0 prefix as octal
          umask = Integer(u)
        end

        if u = params['mode']
          mode = Integer('0'+u)
        end

        if u = params['backlog']
          backlog = Integer(u)
        end
      end
      # Let anyone connect by default
      umask ||= 0

      begin
        old_mask = File.umask(umask)

        if File.exist? @path
          begin
            old = UNIXSocket.new @path
          rescue SystemCallError, IOError
            File.unlink @path
          else
            old.close
            raise "There is already a server bound to: #{@path}"
          end
        end

        @server = UNIXServer.new(@path)
        @server.listen backlog
      ensure
        File.umask old_mask
      end

      if mode
        File.chmod mode, @path
      end
    end

    def unlink_fd
      File.unlink(@path) if File.exist?(@path)
    end

    def env
      { REMOTE_ADDR => "127.0.0.1" }
    end

    def to_s
      "unix://#{@path}"
    end
  end
end
