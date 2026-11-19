# frozen_string_literal: true

require_relative "helper"
require "puma/cluster"

# A step of the wall clock must neither kill a healthy worker nor hide a hung
# one. These tests stub Process.clock_gettime and Time.now for the whole
# process, so this class must stay serial: don't add parallelize_me!.
class TestCluster < PumaTest
  FakeLauncher = Struct.new(:log_writer, :events, :config, :options)

  OPTIONS = { workers: 1, worker_check_interval: 5, worker_timeout: 30, worker_shutdown_timeout: 30 }.freeze

  def setup
    @log_writer = Puma::LogWriter.strings
    @cluster = Puma::Cluster.new FakeLauncher.new(@log_writer, Puma::Events.new, nil, OPTIONS.dup)
    @worker = Puma::Cluster::WorkerHandle.new 0, nil, 0, OPTIONS # no pid, so nothing gets signalled
    @worker.boot!
    @cluster.workers << @worker
  end

  def test_check_workers_ignores_wall_clock_steps
    # wait_workers would reap this process's own children
    @cluster.stub(:wait_workers, nil) do
      after(monotonic: 5, wall: 60) { @cluster.check_workers }
      refute @worker.term?, "worker killed 5s after its check-in:\n#{@log_writer.stdout.string}"

      after(monotonic: 31, wall: -120) { @cluster.check_workers }
      assert_includes @log_writer.stdout.string, "failed to check in within 30 seconds"
    end
  end

  def test_worker_term_ignores_wall_clock_steps
    @worker.term
    after(monotonic: 5, wall: 60) { @worker.term }
    assert_equal "TERM", @worker.signal

    after(monotonic: 31, wall: -120) { @worker.term }
    assert_equal "KILL", @worker.signal
  end

  def test_worker_age_ignores_wall_clock_step
    younger = after(monotonic: 1, wall: -120) { Puma::Cluster::WorkerHandle.new 1, nil, 0, OPTIONS }
    @cluster.workers << younger

    assert_operator younger.uptime, :<, @worker.uptime
    assert_equal [younger], @cluster.workers_to_cull(1)
  end

  private

  # Runs the block as if `monotonic` seconds had passed while the wall clock
  # moved by `wall` seconds.
  def after(monotonic:, wall:, &block)
    real = Process.method :clock_gettime
    mono = ->(id, *args) { real.call(id, *args) + (id == Process::CLOCK_MONOTONIC && args.empty? ? monotonic : 0) }
    Process.stub(:clock_gettime, mono) { Time.stub(:now, Time.now + wall, &block) }
  end
end
