# frozen_string_literal: true

require_relative "helper"

class TestHelper < PumaTest
  def test_with_temp_env
    original_puma_debug_env = ENV["PUMA_DEBUG"]

    with_temp_env({ "PUMA_DEBUG": "1" }, { "APP_ENV" => "test" }) do
      refute_equal original_puma_debug_env, ENV["PUMA_DEBUG"]
      assert_equal "1", ENV["PUMA_DEBUG"]
      assert_equal "test", ENV["APP_ENV"]
    end

    assert_operator original_puma_debug_env, :==, ENV["PUMA_DEBUG"]
    refute ENV.key?("APP_ENV"), "Expected the APP_ENV key to be removed"
  end
end
