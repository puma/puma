require 'puma/plugin'

Puma::Plugin.create do
  def start(launcher)
    STDERR.puts "hello world!!!"
  end
end
