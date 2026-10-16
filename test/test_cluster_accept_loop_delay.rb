# frozen_string_literal: true

require_relative "helper"
require "puma/cluster_accept_loop_delay"

class TestClusterAcceptLoopDelay < PumaTest
  parallelize_me!

  def test_off_when_fewer_than_two_workers
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 1
    )
    assert_equal true, cal_delay.on?

    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 1,
      max_delay: 1
    )
    assert_equal false, cal_delay.on?
  end

  def test_zero_max_delay_always_returns_zero
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 0
    )
    assert_equal false, cal_delay.on?
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 16)
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 42, max_threads: 16)
    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 42 * 42, max_threads: 16)
  end

  def test_zero_busy_threads_plus_todo_always_returns_zero
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 0.005
    )

    assert_equal 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 10)
  end

  def test_linear_increase_with_busy_threads_plus_todo
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 0.05
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: 0, max_threads: 1), 0.001
    assert_in_delta 0.002, cal_delay.calculate(busy_threads_plus_todo: 1, max_threads: 1), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: 25, max_threads: 1), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: 26, max_threads: 1), 0.001
  end

  def test_sub_saturation_and_overload_curve
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 0.05
    )

    # Below thread saturation (u = 0.25), concave sqrt ramp applies stronger early
    # backpressure than linear (0.0014 vs 0.0005)
    sub_saturated = cal_delay.calculate(busy_threads_plus_todo: 1, max_threads: 4)
    assert_in_delta 0.0014, sub_saturated, 0.0001

    # Above thread saturation (u = 13.0, midpoint of 1..25), concave curve applies stronger
    # early backpressure than linear midpoint (0.026)
    overload_mid = cal_delay.calculate(busy_threads_plus_todo: 13, max_threads: 1)
    assert_operator overload_mid, :>, 0.035
    assert_operator overload_mid, :<, 0.05
  end

  def test_always_return_float_when_non_zero
    # Dividing integers accidentally returns 0 so want to make sure we are correctly converting to float before division
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: Integer(5)
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: 0.to_f, max_threads: Integer(1)), 0.001
    assert_equal Float, cal_delay.calculate(busy_threads_plus_todo: Integer(25), max_threads: Integer(1)).class
    assert_in_delta 5, cal_delay.calculate(busy_threads_plus_todo: 25, max_threads: Integer(1)), 0.001
  end

  def test_extreme_busy_values_produce_sensible_delays
    cal_delay = Puma::ClusterAcceptLoopDelay.new(
      workers: 2,
      max_delay: 0.05
    )

    assert_in_delta 0, cal_delay.calculate(busy_threads_plus_todo: -10, max_threads: 5), 0.001
    assert_in_delta 0.05, cal_delay.calculate(busy_threads_plus_todo: Float::INFINITY, max_threads: 5), 0.001
  end
end
