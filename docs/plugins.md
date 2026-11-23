# Plugins

Puma 3.0 added support for plugins that can augment configuration and service
operations.

There are two canonical plugins to aid in the development of new plugins:

* [tmp\_restart](https://github.com/puma/puma/blob/main/lib/puma/plugin/tmp_restart.rb):
  Restarts the server if the file `tmp/restart.txt` is touched
* [heroku](https://github.com/puma/puma-heroku/blob/master/lib/puma/plugin/heroku.rb):
  Packages up the default configuration used by Puma on Heroku (being sunset
  with the release of Puma 5.0)

Plugins are activated in a Puma configuration file (such as `config/puma.rb`)
by adding `plugin "name"`, such as `plugin "heroku"`.

Plugins are activated based on path requirements, so activating the `heroku`
plugin is much like `require "puma/plugin/heroku"`. This allows gems to provide
multiple plugins (as well as unrelated gems to provide Puma plugins).

The `tmp_restart` plugin comes with Puma, so it is always available.

To use the `heroku` plugin, add `puma-heroku` to your Gemfile or install it.

### API

## Server-wide hooks

Plugins can use a couple of hooks at the server level: `start` and `config`.

`start` runs when the server has started and allows the plugin to initiate other
functionality to augment Puma.

`config` runs when the server is being configured and receives a `Puma::DSL`
object that is useful for additional configuration.

Public methods in [`Puma::Plugin`](../lib/puma/plugin.rb) are treated as a
public API for plugins.

## Binder hooks

There's a `Puma::Binder#before_parse` method that allows adding a proc to run before the body of `Puma::Binder#parse`. Example of usage can be found in [that repository](https://github.com/anchordotdev/puma-acme/blob/v0.1.3/lib/puma/acme/plugin.rb#L97-L118) (`before_parse_hook` could be renamed `before_parse`, making monkey patching of [binder.rb](https://github.com/anchordotdev/puma-acme/blob/v0.1.3/lib/puma/acme/binder.rb) unnecessary).

## Community plugins

* [puma-metrics](https://github.com/harmjanblok/puma-metrics) — export Puma metrics to Prometheus
* [puma-plugin-statsd](https://github.com/yob/puma-plugin-statsd) — send Puma metrics to statsd
* [puma-plugin-systemd](https://github.com/sj26/puma-plugin-systemd) — deeper integration with systemd for notify, status and watchdog. Puma 5.1.0 integrated notify and watchdog, which probably conflicts with this plugin. Puma 6.1.0 added status support which obsoletes the plugin entirely.
* [puma-plugin-telemetry](https://github.com/babbel/puma-plugin-telemetry) - telemetry plugin for Puma offering various targets to publish
* [puma-acme](https://github.com/anchordotdev/puma-acme) - automatic SSL/HTTPS certificate provisioning and setup

## Example: stopping Puma via Redis

```ruby
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
#    require './lib/puma/plugin/redis_stop_puma'
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
```
