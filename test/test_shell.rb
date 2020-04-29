require_relative 'helper'

class ShellTest < Minitest::Test
  parallelize_me!

  TESTS_TO_RUN = if Process.respond_to?(:fork)
    %w[t1 t2 t3]
  else
    %w[t1 t2]
  end

  TESTS_TO_RUN.each do |test|
    define_method("test_#{test}") do
      assert system("ruby -rrubygems test/shell/#{test}.rb") # > /dev/null 2>&1")
    end
  end
end unless Puma.windows?
