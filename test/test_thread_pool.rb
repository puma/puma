require_relative "helper"

require "puma/thread_pool"

class TestThreadPool < Minitest::Test

  def teardown
    @pool.shutdown(1) if @pool
  end

  def new_pool(min, max, &block)
    block = proc { } unless block
    @pool = Puma::ThreadPool.new('test', min, max, &block)
  end

  def mutex_pool(min, max, &block)
    block = proc { } unless block
    @pool = MutexPool.new('test', min, max, &block)
  end

  # Wraps ThreadPool work in mutex for better concurrency control.
  class MutexPool < Puma::ThreadPool
    # Wait until the added work is completed before returning.
    # Array argument is treated as a batch of work items to be added.
    # Block will run after work is added but before it is executed on a worker thread.
    def <<(work, &block)
      work = [work] unless work.is_a?(Array)
      with_mutex do
        work.each {|arg| super arg}
        yield if block_given?
        @not_full.wait(@mutex)
      end
    end

    def signal
      @not_full.signal
    end

    # If +wait+ is true, wait until the trim request is completed before returning.
    def trim(force=false, wait: true)
      super(force)
      Thread.pass until @trim_requested == 0 if wait
    end
  end

  def test_append_spawns
    saw = []
    pool = mutex_pool(0, 1) do |work|
      saw << work
    end

    pool << 1
    assert_equal 1, pool.spawned
    assert_equal [1], saw
  end

  def test_thread_name
    skip 'Thread.name not supported' unless Thread.current.respond_to?(:name)
    thread_name = nil
    pool = mutex_pool(0, 1) {thread_name = Thread.current.name}
    pool << 1
    assert_equal('puma test threadpool 001', thread_name)
  end

  def test_converts_pool_sizes
    pool = new_pool('0', '1')

    assert_equal 0, pool.spawned

    pool << 1

    assert_equal 1, pool.spawned
  end

  def test_append_queues_on_max
    pool = new_pool(0, 0) do
      "Hello World!"
    end

    pool << 1
    pool << 2
    pool << 3

    assert_equal 3, pool.backlog
  end

  def test_trim
    pool = mutex_pool(0, 1)

    pool << 1

    assert_equal 1, pool.spawned

    pool.trim
    assert_equal 0, pool.spawned
  end

  def test_trim_leaves_min
    pool = mutex_pool(1, 2)

    pool << [1, 2]

    assert_equal 2, pool.spawned

    pool.trim
    assert_equal 1, pool.spawned

    pool.trim
    assert_equal 1, pool.spawned
  end

  def test_force_trim_doesnt_overtrim
    pool = mutex_pool(1, 2)

    pool.<< [1, 2] do
      assert_equal 2, pool.spawned
      pool.trim true, wait: false
      pool.trim true, wait: false
    end

    assert_equal 1, pool.spawned
  end

  def test_trim_is_ignored_if_no_waiting_threads
    pool = mutex_pool(1, 2)

    pool.<< [1, 2] do
      assert_equal 2, pool.spawned
      pool.trim
      pool.trim
    end

    assert_equal 2, pool.spawned
    assert_equal 0, pool.trim_requested
  end

  def test_autotrim
    pool = mutex_pool(1, 2)

    timeout = 0
    pool.auto_trim! timeout

    pool.<< [1, 2] do
      assert_equal 2, pool.spawned
    end

    start = Time.now
    Thread.pass until pool.spawned == 1 ||
      Time.now - start > 1

    assert_equal 1, pool.spawned
  end

  def test_cleanliness
    values = []
    n = 100

    pool = mutex_pool(1,1) {
      values.push Thread.current[:foo]
      Thread.current[:foo] = :hai
    }

    pool.clean_thread_locals = true

    pool << [1] * n

    assert_equal n,  values.length

    assert_equal [], values.compact
  end

  def test_reap_only_dead_threads
    pool = mutex_pool(2,2) do
      th = Thread.current
      Thread.new {th.join; pool.signal}
      th.kill
    end

    assert_equal 2, pool.spawned

    pool << 1

    assert_equal 2, pool.spawned

    pool.reap

    assert_equal 1, pool.spawned

    pool << 2

    assert_equal 1, pool.spawned

    pool.reap

    assert_equal 0, pool.spawned
  end

  def test_auto_reap_dead_threads
    pool = mutex_pool(2,2) do
      th = Thread.current
      Thread.new {th.join; pool.signal}
      th.kill
    end

    timeout = 0
    pool.auto_reap! timeout

    assert_equal 2, pool.spawned

    pool << 1
    pool << 2

    start = Time.now
    Thread.pass until pool.spawned == 0 ||
      Time.now - start > 1

    assert_equal 0, pool.spawned
  end

  def test_force_shutdown_immediately
    rescued = false

    pool = mutex_pool(0, 1) do
      begin
        pool.with_force_shutdown do
          pool.signal
          sleep
        end
      rescue Puma::ThreadPool::ForceShutdown
        rescued = true
      end
    end

    pool << 1
    pool.shutdown(0)

    assert_equal 0, pool.spawned
    assert rescued
  end

  def test_waiting_on_startup
    pool = new_pool(1, 2)
    assert_equal 1, pool.waiting
  end

  def test_shutdown_with_grace
    timeout = 0.01
    grace = 0.01

    rescued = []
    pool = mutex_pool(2, 2) do
      begin
        pool.with_force_shutdown do
          pool.signal
          sleep
        end
      rescue Puma::ThreadPool::ForceShutdown
        rescued << Thread.current
        sleep
      end
    end

    pool << 1
    pool << 2

    Puma::ThreadPool.stub_const(:SHUTDOWN_GRACE_TIME, grace) do
      pool.shutdown(timeout)
    end
    assert_equal 0, pool.spawned
    assert_equal 2, rescued.length
    refute rescued.compact.any?(&:alive?)
  end

  def test_correct_waiting_count_for_killed_threads
    pool = new_pool(1, 1) { |_| }
    sleep 1

    # simulate our waiting worker thread getting killed for whatever reason
    pool.instance_eval { @workers[0].kill }
    sleep 1
    pool.reap
    sleep 1

    pool << 0
    sleep 1
    assert_equal 0, pool.backlog
  end
end
