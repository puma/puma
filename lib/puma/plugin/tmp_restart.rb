require 'puma/plugin'

Puma::Plugin.create do
  def start(launcher)
    path = File.join("tmp", "restart.txt")

    File.write path, ""

    orig = File.stat(path).mtime

    in_background do
      while true
        sleep 2

        if File.stat(path).mtime > orig
          launcher.restart
          break
        end
      end
    end
  end
end

