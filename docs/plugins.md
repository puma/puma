## Plugins

Puma 3.0 added support for plugins that can augment configuration and service
operations.

2 canonical plugins to look to aid in development of further plugins:

* [tmp\_restart](https://github.com/puma/puma/blob/master/lib/puma/plugin/tmp_restart.rb):
  Restarts the server if the file `tmp/restart.txt` is touched
* [heroku](https://github.com/puma/puma-heroku/blob/master/lib/puma/plugin/heroku.rb):
  Packages up the default configuration used by puma on Heroku

Plugins are activated in a puma configuration file (such as `config/puma.rb'`)
by adding `plugin "name"`, such as `plugin "heroku"`.

Plugins are activated based simply on path requirements so, activating the
`heroku` plugin will simply be doing `require "puma/plugin/heroku"`. This
allows gems to provide multiple plugins (as well as unrelated gems to provide
puma plugins).

The `tmp_restart` plugin is bundled with puma, so it can always be used.

To use the `heroku` plugin, add `puma-heroku` to your Gemfile or install it.

### API

## Server-wide hooks

Plugins can use a couple of hooks at server level: `start` and `config`.

`start` runs when the server has started and allows the plugin to start other
functionality to augment puma.

`config` runs when the server is being configured and is passed a `Puma::DSL`
object that can be used to add additional configuration.

Any public methods in `Puma::Plugin` are the public API that any plugin may
use.

## Per request hooks

`#on_before_rack(env)` will be called right before the Rack application is
invoked. The called hook may modify `env` just like any Rack middleware.

`#on_after_rack(env, headers, io)` will be called after the Rack application
has completed its execution and before any response content is written to the
client. A plugin may take over from here by returning an object that responds
to `#stream?` with a truthy value. Check out `lib/puma/stream_client.rb` to
know more about this interface.

If more than one plugin arises interest in taking over, an exception will
be happen and Puma will serve a 500.
