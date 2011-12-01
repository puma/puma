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

      if ary = env['rack.after_reply']
        ary << lambda { log(env, status, header, began_at) }
      else
        body = BodyProxy.new(body) { log(env, status, header, began_at) }
      end

      [status, header, body]
    end
  end
end
