require_relative "helper"

require 'puma/control_cli'

class TestPumaControlCli < Minitest::Test
  def test_config_file
    control_cli = Puma::ControlCLI.new ["--config-file", "test/config/state_file_testing_config.rb", "halt"]
    assert_equal "t3-pid", control_cli.instance_variable_get("@pidfile")
  end
end
