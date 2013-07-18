require 'rack/commonlogger'

module Rack
  # Patch CommonLogger to use after_reply.
  #
  # Simply request this file and CommonLogger will be a bit more 
  # efficient.
  class CommonLogger
    remove_method :call

    def call(env)
      began_at = Time.now
      status, header, body = @app.call(env)
      header = Utils::HeaderHash.new(header)

      # If we've been hijacked, then output a special line
      if env['rack.hijack_io']
        log_hijacking(env, 'HIJACK', header, began_at)
      elsif ary = env['rack.after_reply']
        ary << lambda { log(env, status, header, began_at) }
      else
        body = BodyProxy.new(body) { log(env, status, header, began_at) }
      end

      [status, header, body]
    end

    HIJACK_FORMAT = %{%s - %s [%s] "%s %s%s %s" HIJACKED -1 %0.4f\n}

    def log_hijacking(env, status, header, began_at)
      now = Time.now

      logger = @logger || env['rack.errors']
      logger.write HIJACK_FORMAT % [
        env['HTTP_X_FORWARDED_FOR'] || env["REMOTE_ADDR"] || "-",
        env["REMOTE_USER"] || "-",
        now.strftime("%d/%b/%Y %H:%M:%S"),
        env["REQUEST_METHOD"],
        env["PATH_INFO"],
        env["QUERY_STRING"].empty? ? "" : "?"+env["QUERY_STRING"],
        env["HTTP_VERSION"],
        now - began_at ]
    end
  end
end
