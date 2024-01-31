# frozen_string_literal: true

module TestPuma
  module Assertions
    def assert_start_with(obj, str, msg = nil)
      msg = message(msg) {
        "Expected\n#{obj}\nto start with #{str}"
      }
      assert_respond_to obj, :start_with?
      assert obj.start_with?(str), msg
    end

    def assert_end_with(obj, str, msg = nil)
      msg = message(msg) {
        "Expected\n#{obj}\nto end with #{str}"
      }
      assert_respond_to obj, :end_with?
      assert obj.end_with?(str), msg
    end

    # if obj is longer than 80 characters, show as string, not inspected
    def assert_match(matcher, obj, msg = nil)
      msg = if obj.length < 80
        message(msg) { "Expected #{mu_pp matcher} to match #{mu_pp obj}" }
      else
        message(msg) { "Expected #{mu_pp matcher} to match:\n#{obj}\n" }
      end
      assert_respond_to matcher, :"=~"
      matcher = Regexp.new Regexp.escape matcher if String === matcher
      assert matcher =~ obj, msg
    end
  end
end

module Minitest
  module Assertions
    prepend TestPuma::Assertions
  end
end
