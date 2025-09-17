# frozen_string_literal: true

require_relative "helper"
require "puma/cluster_accept_loop_delay"

class TestClusterAcceptLoopDelay < PumaTest
  parallelize_me!

  def test_zero_max_delay_always_returns_zero
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      max_delay: 0
    )
    assert_equal false, cal_delay.on?
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 16)
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 42, max_threads: 16)
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 42 * 42, max_threads: 16)
  end

  def test_zero_busy_threads_plus_todo_always_returns_zero
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      max_delay: 0.005
    )

    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 10)
  end

  def test_linear_increase_with_busy_threads_plus_todo
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      max_delay: 0.05
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 1), 0.001
    assert_in_delta 0.002, cal_delay.calculate(busy_threads_plus_todo: 1, max_threads: 1), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: 25, max_threads: 1), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: 26, max_threads: 1), 0.001
  end

  def test_always_return_float_when_non_zero
    # Dividing integers accidentally returns 0 so want to make sure we are correctly converting to float before division
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      max_delay: Integer(5)
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: 0.to_f, max_threads: Integer(1)), 0.001
    assert_equal Float, cal_delay.calculate(busy_threads_plus_todo: Integer(25), max_threads: Integer(1)).class
    assert_in_delta 5, cal_delay.calculate(busy_threads_plus_todo: 25, max_threads: Integer(1)), 0.001
  end

  def test_extreme_busy_values_produce_sensible_delays
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      max_delay: 0.05
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: -10, max_threads: 5), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: Float::INFINITY, max_threads: 5), 0.001
  end
end
