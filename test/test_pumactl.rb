require "test_helper"

require 'puma/control_cli'

class TestPumaControlCli < Minitest::Test
  def test_config_file
    Puma::ControlCLI.new ["halt", "--config-file", 'test/config/settings.rb']
  end
end
