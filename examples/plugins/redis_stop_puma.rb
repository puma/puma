require 'puma/plugin'
require 'redis'

# How to stop Puma on Heroku
# - You can't use normal methods because the dyno is not accessible
# - There's no file system, no way to send signals
# but ...
# - You can use Redis or Memcache; any network distributed key-value
#   store

# 1. Add this plugin to your 'lib' directory
# 2. In the `puma.rb` config file add the following lines
#    === Plugins ===
#    require './lib/puma/plugins/redis_stop_puma'
#    plugin 'redis_stop_puma'
# 3. Now, when you set the redis key "puma::restart::web.1", your web.1 dyno
#    will restart
# 4. Sniffing the Heroku logs for R14 errors is application (and configuration)
#    specific. I use the Logentries service, watch for the pattern and the call
#    a webhook back into my app to set the Redis key. YMMV

# You can test this locally by setting the DYNO environment variable when
# when starting puma, e.g. `DYNO=pants.1 puma`

Puma::Plugin.create do
  def start(launcher)

    hostname = ENV['DYNO']
    return unless hostname

    redis = Redis.new(url: ENV.fetch('REDIS_URL', nil))
    return unless redis.ping == 'PONG'

    in_background do
      while true
        sleep 2
        if message = redis.get("puma::restart::#{hostname}")
          redis.del("puma::restart::#{hostname}")
          $stderr.puts message
          launcher.stop
          break
        end
      end
    end
  end
end
