# frozen_string_literal: true

require_relative "helper"

require "puma/request"

class TestNormalize < Minitest::Test
  parallelize_me!

  include Puma::Request

  def test_comma_headers
    env = {
      "HTTP_X_FORWARDED_FOR" => "1.1.1.1",
      "HTTP_X_FORWARDED,FOR" => "2.2.2.2",
    }

    req_env_post_parse env

    expected = {
      "HTTP_X_FORWARDED_FOR" => "1.1.1.1",
    }

    assert_equal expected, env

    # Test that the iteration order doesn't matter

    env = {
      "HTTP_X_FORWARDED,FOR" => "2.2.2.2",
      "HTTP_X_FORWARDED_FOR" => "1.1.1.1",
    }

    req_env_post_parse env

    expected = {
      "HTTP_X_FORWARDED_FOR" => "1.1.1.1",
    }

    assert_equal expected, env
  end

  def test_unmaskable_headers
    env = {
      "HTTP_CONTENT,LENGTH" => "100000",
      "HTTP_TRANSFER,ENCODING" => "chunky"
    }

    req_env_post_parse env

    expected = {
      "HTTP_CONTENT,LENGTH" => "100000",
      "HTTP_TRANSFER,ENCODING" => "chunky"
    }

    assert_equal expected, env
  end
end
