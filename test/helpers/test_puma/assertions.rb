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

    # These methods is modified based on https://github.com/rails/rails/blob/7-1-stable/activesupport/lib/active_support/testing/method_call_assertions.rb
    ### BEGIN
    def assert_called_on_instance_of(klass, method_name, message = nil, times: 1, returns: nil)
      times_called = 0
      klass.send(:define_method, :"stubbed_#{method_name}") do |*|
        times_called += 1

        returns
      end

      klass.send(:alias_method, :"original_#{method_name}", method_name)
      klass.send(:alias_method, method_name, :"stubbed_#{method_name}")

      yield

      error = "Expected #{method_name} to be called #{times} times, but was called #{times_called} times"
      error = "#{message}.\n#{error}" if message

      assert_equal times, times_called, error
    ensure
      klass.send(:alias_method, method_name, :"original_#{method_name}")
      klass.send(:undef_method, :"original_#{method_name}")
      klass.send(:undef_method, :"stubbed_#{method_name}")
    end

    def assert_not_called_on_instance_of(klass, method_name, message = nil, &block)
      assert_called_on_instance_of(klass, method_name, message, times: 0, &block)
    end
    ### END
  end
end

module Minitest
  module Assertions
    prepend TestPuma::Assertions
  end
end
