## Plugins

Puma 3.0 added support for plugins that can augment configuration and service
operations.

There are two canonical plugins to aid in the development of new plugins:

* [tmp\_restart](https://github.com/puma/puma/blob/master/lib/puma/plugin/tmp_restart.rb):
  Restarts the server if the file `tmp/restart.txt` is touched
* [heroku](https://github.com/puma/puma-heroku/blob/master/lib/puma/plugin/heroku.rb):
  Packages up the default configuration used by Puma on Heroku (being sunset
  with the release of Puma 5.0)

Plugins are activated in a Puma configuration file (such as `config/puma.rb'`)
by adding `plugin "name"`, such as `plugin "heroku"`.

Plugins are activated based on path requirements so, activating the `heroku`
plugin is much like `require "puma/plugin/heroku"`. This allows gems to provide
multiple plugins (as well as unrelated gems to provide Puma plugins).

The `tmp_restart` plugin comes with Puma, so it is always available.

To use the `heroku` plugin, add `puma-heroku` to your Gemfile or install it.

### Development

When developing a plugin, there are 2 conventions that must be met:
- A plugin must be defined using the `Puma::Plugin.create` API;
- A Ruby file containing the creation of a plugin using the above method must be located under the `puma/plugin` load path.

The name of the file where `Puma::Plugin.create` is called will be used as plugin's name during its registration.

This name can then be used to activate the plugin in the Puma configuration file:
```ruby
# In Puma configuration file
plugin "name"
```

In case code that defines the plugin was not executed by the time the Puma config file is evaluated, 
Puma will attempt to load the plugin by requiring `puma/plugin/<plugin_name>`.

This means that, if a Puma plugin is implemented in a 3rd-party gem, it should be defined in `<gem_root>/lib/puma/plugins/<plugin_name>`.

It is also possible to circumvent the conventions around path structure in order to preserve the directory structure of the 3rd-party gem.

First, you can override the name of your plugin during definition:

```ruby
# In <gem_root>/lib/integrations/puma/plugin.rb
Puma::Plugin.create(:custom_plugin) do
  # ...
end
```

The above plugin will be registered as `custom_plugin` instead of `plugin`. It will be available for 
activation in the configuration file using `plugin "custom_plugin"`.

However, it will only be available for activation in case the code that contains its definition 
is evaluated before the config file. Otherwise Puma will fail to load it by attempting to require 
non-existent `puma/plugins/custom_plugin`.

In order to make the unconventional directory structure work, the correct path to the plugin 
definition must be provided during activation:

```ruby
# In Puma configuration file
plugin "name", "<gem_root>/lib/integrations/puma/plugin"
```

### API

## Server-wide hooks

Plugins can use a couple of hooks at the server level: `start` and `config`.

`start` runs when the server has started and allows the plugin to initiate other
functionality to augment Puma.

`config` runs when the server is being configured and receives a `Puma::DSL`
object that is useful for additional configuration.

Public methods in [`Puma::Plugin`](../lib/puma/plugin.rb) are treated as a
public API for plugins.
