require 'test/unit'

require 'puma/thread_pool'

class TestThreadPool < Test::Unit::TestCase

  def teardown
    @pool.shutdown if @pool
  end

  def new_pool(min, max, &block)
    block = proc { } unless block
    @pool = Puma::ThreadPool.new(min, max, &block)
  end

  def pause
    sleep 0.2
  end

  def test_append_spawns
    saw = []

    pool = new_pool(0, 1) do |work|
      saw << work
    end

    pool << 1

    pause

    assert_equal [1], saw
    assert_equal 1, pool.spawned
  end

  def test_converts_pool_sizes
    pool = new_pool('0', '1')

    assert_equal 0, pool.spawned

    pool << 1

    assert_equal 1, pool.spawned
  end

  def test_append_queues_on_max
    finish = false
    pool = new_pool(0, 1) { Thread.pass until finish }

    pool << 1
    pool << 2
    pool << 3

    pause

    assert_equal 2, pool.backlog

    finish = true
  end

  def test_trim
    pool = new_pool(0, 1)

    pool << 1

    pause

    assert_equal 1, pool.spawned
    pool.trim

    pause
    assert_equal 0, pool.spawned
  end

  def test_trim_leaves_min
    finish = false
    pool = new_pool(1, 2) { Thread.pass until finish }

    pool << 1
    pool << 2

    finish = true

    pause

    assert_equal 2, pool.spawned
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
end
