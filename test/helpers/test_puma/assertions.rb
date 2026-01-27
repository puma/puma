# frozen_string_literal: true

module TestPuma
  module Assertions

    # iso8601 2022-12-14T00:05:49Z
    RE_8601 = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/

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

    def refute_start_with(obj, str, msg = nil)
      msg = message(msg) {
        "Expected\n#{obj}\nto not start with #{str}"
      }
      assert_respond_to obj, :start_with?
      refute obj.start_with?(str), msg
    end

    def refute_end_with(obj, str, msg = nil)
      msg = message(msg) {
        "Expected\n#{obj}\nto not end with #{str}"
      }
      assert_respond_to obj, :end_with?
      refute obj.end_with?(str), msg
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

    def assert_hash(exp, act)
      exp.each do |exp_k, exp_v|
        if exp_v.is_a? Class
          assert_instance_of exp_v, act[exp_k], "Key #{exp_k} has invalid class"
        elsif exp_v.is_a? ::Regexp
          assert_match exp_v, act[exp_k], "Key #{exp_k} has invalid match"
        elsif exp_v.is_a?(Array) || exp_v.is_a?(Range)
          assert_includes exp_v, act[exp_k], "Key #{exp_k} isn't included"
        else
          assert_equal exp_v, act[exp_k], "Key #{exp_k} bad value"
        end
      end
    end

    def assert_extend_timeout_usec(message, msg = nil)
      assert_match(/\AEXTEND_TIMEOUT_USEC=\d+\z/, message, msg)
      message.split("=", 2).last.to_i
    end
  end
end

module Minitest
  module Assertions
    prepend TestPuma::Assertions
  end
end
