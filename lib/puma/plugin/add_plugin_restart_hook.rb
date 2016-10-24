# ### Usage
#
# This plugin is used indirectly by plugin developers to allow restart-triggered **instances** plugins like below.
# Normally, a plain `dsl.on_restart` block would be fine.
#
#     require 'puma/plugin'
#
#     Puma::Plugin.create do
#       def config(dsl)
#         dsl.plugin :add_plugin_restart_hook
#       end
#
#       def restart(launcher)
#         # do something on_restart
#       end
#     end
#
require 'puma/plugin'

Puma::Plugin.create do
  def config(dsl)
    Puma::Launcher.class_eval do
      def fire_plugins_restart
        @config.plugins.fire_restarts self
      end
    end

    Puma::PluginLoader.class_eval do
      def fire_restarts(launcher)
        @instances.each do |i|          
          i.restart(launcher) if i.respond_to? :restart
        end
      end
    end

    dsl.on_restart { |launcher| launcher.fire_plugins_restart }
  end
end
