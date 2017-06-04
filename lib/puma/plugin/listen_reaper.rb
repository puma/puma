# Usage: add `plugin :listen_reaper` to `config/puma.rb`
require 'puma/plugin'

# This plugin stops all Listen instances from gem listen upon restart.
# This prevents too many fsevent_watch (macOS only) processes and
# cleans up unused system resources between restarts.
Puma::Plugin.create do
  def config(dsl)
    # add :restart hook to plugin 
    dsl.plugin :add_plugin_restart_hook
  end

  # call #stop on all FSEvent instances
  # this should close pipes and make fsevent_watch'es die
  def restart(_launcher)
    return unless defined? Listen
    ObjectSpace.each_object(Listen, &:stop)
  end
end
