require_relative "helper"
require_relative "helpers/tmp_path"

require 'puma/state_file'

class TestStateFile < Minitest::Test
  include TmpPath

  def test_load_empty_value_as_nil
    state_path = tmp_path('.state')
    File.write state_path, <<-STATE
---
pid: 123456
control_url:
control_auth_token:
running_from: "/path/to/app"
    STATE

    sf = Puma::StateFile.new
    sf.load(state_path)
    assert_equal 123456, sf.pid
    assert_equal '/path/to/app', sf.running_from
    assert_nil sf.control_url
    assert_nil sf.control_auth_token

  end
end
