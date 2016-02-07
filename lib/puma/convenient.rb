require 'puma/launcher'
require 'puma/configuration'

module Puma
  def self.run(opts={})
    cfg = Puma::Configuration.new do |c|
      if port = opts[:port]
        c.port port
      end

      c.quiet

      yield c
    end

    cfg.clamp

    events = Puma::Events.strings

    launcher = Puma::Launcher.new cfg, :events => events
    launcher.run
  end
end
