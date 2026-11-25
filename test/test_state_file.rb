# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"

require 'puma/state_file'

class TestStateFile < PumaTest
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

  def test_load_keeps_numeric_looking_token_as_string
    state_path = tmp_path('.state')
    %w[0123 1.50 1234].each do |token|
      sf = Puma::StateFile.new
      sf.pid = 12345
      sf.control_auth_token = token
      sf.save state_path

      loaded = Puma::StateFile.new
      loaded.load state_path
      assert_equal token, loaded.control_auth_token
      assert_kind_of String, loaded.control_auth_token
      assert_equal 12345, loaded.pid
      assert_kind_of Integer, loaded.pid
    end
  end
end
