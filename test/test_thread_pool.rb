require_relative "helper"

require "puma/thread_pool"

class TestThreadPool < Minitest::Test

  def teardown
    @pool.shutdown(1) if @pool
  end

  def new_pool(min, max, &block)
    block = proc { } unless block
    @work_mutex = Mutex.new
    @work_done = ConditionVariable.new
    @pool = Puma::ThreadPool.new(min, max, &block)
  end

  def pause
    sleep 0.2
  end

  def test_append_spawns
    saw = []
    thread_name = nil

    pool = new_pool(0, 1) do |work|
      @work_mutex.synchronize do
        saw << work
        thread_name = Thread.current.name if Thread.current.respond_to?(:name)
        @work_done.signal
      end
    end

    pool << 1

    @work_mutex.synchronize do
      @work_done.wait(@work_mutex, 5)
      assert_equal 1, pool.spawned
      assert_equal [1], saw
      assert_equal('puma threadpool 001', thread_name) if Thread.current.respond_to?(:name)
    end
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
    pool = new_pool(0, 1) do |work|
      @work_mutex.synchronize do
        @work_done.signal
      end
    end

    pool << 1

    @work_mutex.synchronize do
      @work_done.wait(@work_mutex, 5)
      assert_equal 1, pool.spawned
    end

    pool.trim
    pool.instance_variable_get(:@workers).first.join

    assert_equal 0, pool.spawned
  end

  def test_trim_leaves_min
    pool = new_pool(1, 2) do |work|
      @work_mutex.synchronize do
        @work_done.signal
      end
    end

    pool << 1
    pool << 2

    @work_mutex.synchronize do
      @work_done.wait(@work_mutex, 5)
      assert_equal 2, pool.spawned
    end

    pool.trim
    pause
    assert_equal 1, pool.spawned


    pool.trim
    pause
    assert_equal 1, pool.spawned
  end

  def test_force_trim_doesnt_overtrim
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    assert_equal 2, pool.spawned
    pool.trim true
    pool.trim true

    finish = true

    pause

    assert_equal 1, pool.spawned
  end

  def test_trim_is_ignored_if_no_waiting_threads
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    assert_equal 2, pool.spawned
    pool.trim
    pool.trim

    assert_equal 0, pool.trim_requested

    finish = true

    pause
  end

  def test_autotrim
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    assert_equal 2, pool.spawned

    finish = true

    pause

    assert_equal 2, pool.spawned

    pool.auto_trim! 1

    sleep 1

    pause

    assert_equal 1, pool.spawned
  end

  def test_cleanliness
    values = []
    n = 100
    mutex = Mutex.new

    finished = false

    pool = new_pool(1,1) {
      mutex.synchronize { values.push Thread.current[:foo] }
      Thread.current[:foo] = :hai
      Thread.pass until finished
    }

    pool.clean_thread_locals = true

    n.times { pool << 1 }

    finished = true

    pause

    assert_equal n,  values.length

    assert_equal [], values.compact
  end

  def test_reap_only_dead_threads
    pool = new_pool(2,2) { Thread.current.kill }

    assert_equal 2, pool.spawned

    pool << 1

    pause

    assert_equal 2, pool.spawned

    pool.reap

    assert_equal 1, pool.spawned

    pool << 2

    pause

    assert_equal 1, pool.spawned

    pool.reap

    assert_equal 0, pool.spawned
  end

  def test_auto_reap_dead_threads
    pool = new_pool(2,2) { Thread.current.kill }

    pool.auto_reap! 0.1

    pause

    assert_equal 2, pool.spawned

    pool << 1
    pool << 2

    pause

    assert_equal 0, pool.spawned
  end

  def test_force_shutdown_immediately
    finish = false
    rescued = false

    pool = new_pool(0, 1) do |work|
      begin
        @work_mutex.synchronize do
          @work_done.signal
        end
        Thread.pass until finish
      rescue Puma::ThreadPool::ForceShutdown
        rescued = true
      end
    end

    pool << 1

    @work_mutex.synchronize do
      @work_done.wait(@work_mutex, 5)
      pool.shutdown(0)
      finish = true
      assert_equal 0, pool.spawned
      assert rescued
    end
  end
end
