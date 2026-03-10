# frozen_string_literal: true

require_relative "helper"
require "puma/workers_auto"

class TestWorkersAuto < PumaTest
  parallelize_me!

  def setup
    require 'concurrent/utility/processor_counter'
  end

  def stub_cgroups_v2(content)
    v2_path = Puma::WorkersAuto::CGROUPS_V2_CPU_MAX
    File.stub(:exist?, ->(path) { path == v2_path }) do
      File.stub(:read, content) do
        yield
      end
    end
  end

  def stub_cgroups_v1(quota:, period:)
    v1_quota  = Puma::WorkersAuto::CGROUPS_V1_QUOTA_US
    v1_period = Puma::WorkersAuto::CGROUPS_V1_PERIOD_US
    reads = [quota.to_s, period.to_s]
    File.stub(:exist?, ->(path) { path == v1_quota || path == v1_period }) do
      File.stub(:read, ->(_path) { reads.shift }) do
        yield
      end
    end
  end

  # ── cgroups v2 ────────────────────────────────────────────────────────────

  def test_cgroups_v2_returns_ceiled_cpu_count
    stub_cgroups_v2("200000 100000") do
      assert_equal 2, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_v2_fractional_rounds_up
    stub_cgroups_v2("150000 100000") do
      assert_equal 2, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_v2_max_falls_back_to_concurrent
    stub_cgroups_v2("max 100000") do
      expected = Integer(Concurrent.available_processor_count)
      assert_equal expected, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_v2_enforces_minimum_one
    stub_cgroups_v2("50000 100000") do
      assert_equal 1, Puma::WorkersAuto.count
    end
  end

  # ── cgroups v1 ────────────────────────────────────────────────────────────

  def test_cgroups_v1_returns_ceiled_cpu_count
    stub_cgroups_v1(quota: 200_000, period: 100_000) do
      assert_equal 2, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_v1_unlimited_quota_falls_back_to_concurrent
    stub_cgroups_v1(quota: -1, period: 100_000) do
      expected = Integer(Concurrent.available_processor_count)
      assert_equal expected, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_v1_enforces_minimum_one
    stub_cgroups_v1(quota: 50_000, period: 100_000) do
      assert_equal 1, Puma::WorkersAuto.count
    end
  end

  # ── fallback / error cases ─────────────────────────────────────────────────

  def test_no_cgroups_uses_concurrent
    File.stub(:exist?, false) do
      expected = Integer(Concurrent.available_processor_count)
      assert_equal expected, Puma::WorkersAuto.count
    end
  end

  def test_cgroups_file_error_falls_back_to_concurrent
    v2_path = Puma::WorkersAuto::CGROUPS_V2_CPU_MAX
    File.stub(:exist?, ->(path) { path == v2_path }) do
      File.stub(:read, ->(_path) { raise Errno::EACCES, "permission denied" }) do
        expected = Integer(Concurrent.available_processor_count)
        assert_equal expected, Puma::WorkersAuto.count
      end
    end
  end

  def test_requires_concurrent_ruby
    Puma::WorkersAuto.stub(:require_processor_counter, -> { raise LoadError, "concurrent-ruby not available" }) do
      assert_raises(LoadError) { Puma::WorkersAuto.count }
    end
  end
end
