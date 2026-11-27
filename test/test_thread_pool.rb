# frozen_string_literal: true

require_relative "helper"

require "puma/thread_pool"

class TestThreadPool < PumaTest

  parallelize_me!

  def teardown
    @pool.shutdown(1) if defined?(@pool)
  end

  def new_pool(min, max, max_io_threads: 0, pool_shutdown_grace_time: nil, &block)
    block = proc { } unless block
    options = {
      min_threads: min,
      max_threads: max,
      max_io_threads: max_io_threads,
      pool_shutdown_grace_time: pool_shutdown_grace_time,
    }
    @pool = Puma::ThreadPool.new("tst", options, &block)
  end

  def wait_until(timeout = 1)
    Timeout.timeout(timeout) { sleep 0.01 until yield }
  end

  def mutex_pool(min, max, pool_shutdown_grace_time: nil, &block)
    block = proc { } unless block
    options = {
      min_threads: min,
      max_threads: max,
      pool_shutdown_grace_time: pool_shutdown_grace_time,
    }
    @pool = MutexPool.new("tst", options, &block)
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
        yield if block
        @not_full.wait(@mutex)
      end
    end

    def signal
      @not_full.signal
    end

    # If +wait+ is true, wait until the trim request is completed before returning.
    def trim(force=false, wait: true)
      super(force)

      return unless wait
      loop do
        # While we wait until @trim_requested is 0, the test might inspect other values
        # such as @spawned which may be modified after this variable is modified in the loop
        # Lock for race safety
        with_mutex do
          return if @trim_requested == 0
        end
        Thread.pass
      end
    end
  end

  def test_append_spawns
    saw = []
    pool = mutex_pool(0, 1) do |_processor, work|
      saw << work
    end

    pool << 1
    assert_equal 1, pool.spawned
    assert_equal [1], saw
  end

  def test_thread_name
    skip "Thread.name not supported" unless Thread.current.respond_to?(:name)
    thread_name = nil
    pool = mutex_pool(0, 1) {thread_name = Thread.current.name}
    pool << 1
    assert_equal("puma tst tp 001", thread_name)
  end

  def test_thread_name_linux
    skip "Thread.name not supported" unless Thread.current.respond_to?(:name)

    task_dir = File.join("", "proc", Process.pid.to_s, "task")
    skip "This test only works under Linux and MRI Ruby with appropriate permissions" if !(File.directory?(task_dir) && File.readable?(task_dir) && Puma::IS_MRI)

    expected_thread_name = "puma tst tp 001"
    found_thread = false
    pool = mutex_pool(0, 1) do
      # Read every /proc/<pid>/task/<tid>/comm file to find the thread name
      Dir.entries(task_dir).select {|tid| File.directory?(File.join(task_dir, tid))}.each do |tid|
        comm_file = File.join(task_dir, tid, "comm")
        next unless File.file?(comm_file) && File.readable?(comm_file)

        if File.read(comm_file).strip == expected_thread_name
          found_thread = true
          break
        end
      end
    end
    pool << 1

    assert(found_thread, "Did not find thread with name '#{expected_thread_name}'")
  end

  def test_converts_pool_sizes
    pool = new_pool("0", "1")

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

  def test_thread_start_hook
    started = Queue.new
    options = {
      min_threads: 0,
      max_threads: 1,
      before_thread_start: [
        {
          id: nil,
          block: proc { started << 1 },
          cluster_only: false,
        }
      ]
    }
    block = proc { }
    pool = MutexPool.new("tst", options, &block)

    pool << 1

    assert_equal 1, pool.spawned
    assert_equal 1, started.length
  end

  def test_thread_start_hook_with_server
    dummy_server_obj = Struct.new(:thread_pool).new
    started = Queue.new
    options = {
      min_threads: 0,
      max_threads: 1,
      before_thread_start: [
        {
          id: nil,
          block: proc {|server| started << server },
          cluster_only: false,
        }
      ]
    }
    block = proc { }
    pool = MutexPool.new("tst", options, server: dummy_server_obj, &block)

    pool << 1

    assert_equal 1, pool.spawned
    assert_respond_to started.pop, :update_thread_pool_min_max
  end

  def test_out_of_band_hook
    out_of_band_called = Queue.new
    options = {
      min_threads: 0,
      max_threads: 1,
      out_of_band: [
        {
          id: nil,
          block: proc { out_of_band_called << 1 },
          cluster_only: false,
        }
      ]
    }
    block = proc { true }
    pool = MutexPool.new("tst", options, &block)

    pool << 1

    assert_equal 1, pool.spawned
    assert_equal 1, out_of_band_called.length
  end

  def test_trim
    pool = mutex_pool(0, 1)

    pool << 1

    assert_equal 1, pool.spawned

    pool.trim(wait: true)
    assert_equal 0, pool.spawned
  end

  def test_trim_leaves_min
    pool = mutex_pool(1, 2)

    pool << [1, 2]

    assert_equal 2, pool.spawned

    pool.trim(wait: true)
    assert_equal 1, pool.spawned

    pool.trim(wait: true)
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

  def test_force_trim_is_honored_while_pool_is_busy
    started = Queue.new
    release = Queue.new
    pool = new_pool(0, 3) do
      started << true
      release.pop
    end
    4.times { |i| pool << i } # 4 because 3 threads busy, 1 item queued

    3.times { started.pop }

    assert_equal 3, pool.spawned
    assert_equal 1, pool.backlog

    pool.trim(true)

    assert_equal 1, pool.trim_requested

    release << true
    wait_until { pool.spawned == 2 }

    assert_equal 2, pool.spawned
    assert_equal 1, pool.backlog
    assert_equal 0, pool.trim_requested
  ensure
    3.times { release << true }
  end

  def test_force_trim_unblocks_wait_until_not_full
    started = Queue.new
    release = Queue.new
    pool = new_pool(1, 3) do
      started << true
      release.pop
    end

    3.times { |i| pool << i }
    3.times { started.pop }

    unblocked = Queue.new
    waiter = Thread.new do
      pool.wait_until_not_full
      unblocked << true
    end
    wait_until { waiter.stop? }

    pool.trim(true)
    release << true

    assert Timeout.timeout(1) { unblocked.pop }
    assert_equal 2, pool.spawned
  ensure
    3.times { release << true }
    waiter&.join(1)
  end

  def test_update_min_max_shrinks_idle_pool_without_auto_trim
    pool = new_pool(4, 4)
    assert_equal 4, pool.spawned
    assert_equal 4, pool.waiting

    pool.update_min_max(2, 2)
    wait_until { pool.spawned == 2 && pool.waiting == 2 }

    assert_equal 2, pool.spawned
    assert_equal 2, pool.waiting
  end

  def test_update_min_max_lower_then_raise_does_not_overtrim
    started = Queue.new
    release = Queue.new
    exited = Queue.new
    options = {
      min_threads: 1,
      max_threads: 4,
      before_thread_exit: [{ id: nil, block: proc { exited << true }, cluster_only: false }]
    }
    pool = @pool = Puma::ThreadPool.new("tst", options) do
      started << true
      release.pop
    end

    6.times { |i| pool << i }
    4.times { started.pop }
    assert_equal 2, pool.backlog

    pool.update_min_max(1, 2)
    pool.update_min_max(1, 4)

    6.times { release << true }
    wait_until { pool.waiting == 4 && pool.backlog == 0 }

    assert_equal 4, pool.spawned
    assert_equal 0, exited.size
  ensure
    6.times { release << true }
  end

  def test_update_min_max_raising_min_prevents_overtrim_from_pending_trims
    started = Queue.new
    release = Queue.new
    pool = new_pool(1, 4) do
      started << true
      release.pop
    end

    4.times { |i| pool << i }
    4.times { started.pop }

    2.times { pool.trim(true) }
    assert_equal 2, pool.trim_requested

    pool.update_min_max(3, 4)
    assert_equal 1, pool.trim_requested

    4.times { release << true }
    wait_until { pool.waiting == 3 }

    assert_equal 3, pool.spawned
    assert_equal 0, pool.trim_requested
  ensure
    4.times { release << true }
  end

  def test_update_min_max_with_io_threads_does_not_overtrim_normal_threads
    io_started = Queue.new
    io_release = Queue.new
    normal_started = Queue.new
    normal_release = Queue.new

    pool = new_pool(0, 3, max_io_threads: 2) do |processor, kind|
      if kind == :io
        processor.mark_as_io_thread!
        io_started << true
        io_release.pop
      else
        normal_started << true
        normal_release.pop
      end
    end

    2.times { pool << :io }
    2.times { io_started.pop }

    5.times { pool << :normal }
    3.times { normal_started.pop }

    assert_equal 5, pool.spawned
    assert_equal 2, pool.backlog

    pool.update_min_max(0, 2)

    2.times { io_release << true }
    wait_until { pool.spawned == 3 }

    normal_release << true
    wait_until { pool.spawned == 2 }
    assert_equal 2, pool.backlog

    4.times { normal_release << true }
    wait_until { pool.waiting == 2 && pool.backlog == 0 }

    assert_equal 2, pool.spawned
  ensure
    2.times { io_release << true }
    5.times { normal_release << true }
  end

  def test_update_min_max_after_reap_does_not_overtrim
    started = Queue.new
    release = Queue.new
    pool = new_pool(1, 4) do
      started << true
      release.pop
    end

    4.times { |i| pool << i }
    4.times { started.pop }

    pool.update_min_max(1, 2)

    victim = pool.instance_variable_get(:@processors).first
    victim.kill
    victim.join
    pool.reap

    assert_equal 3, pool.spawned

    3.times { release << true }
    wait_until { pool.waiting == 2 }

    assert_equal 2, pool.spawned
  ensure
    4.times { release << true }
  end

  def test_update_min_max_zero_drains_queued_work_before_last_thread_exits
    started = Queue.new
    release = Queue.new
    processed = Queue.new
    pool = new_pool(0, 2) do
      started << true
      release.pop
      processed << true
    end

    5.times { |i| pool << i }
    2.times { started.pop }

    assert_equal 2, pool.spawned
    assert_equal 3, pool.backlog

    pool.update_min_max(0, 0)

    release << true
    wait_until { pool.spawned == 1 }
    assert_equal 3, pool.backlog

    4.times { release << true }
    wait_until { pool.spawned == 0 }

    assert_equal 5, processed.size
  ensure
    5.times { release << true }
  end

  def test_update_min_max_raising_max_unblocks_wait_until_not_full
    started = Queue.new
    release = Queue.new
    pool = new_pool(1, 2) do
      started << true
      release.pop
    end

    2.times { |i| pool << i }
    2.times { started.pop }

    unblocked = Queue.new
    waiter = Thread.new do
      pool.wait_until_not_full
      unblocked << true
    end
    wait_until { waiter.stop? }

    pool.update_min_max(1, 3)

    assert Timeout.timeout(1) { unblocked.pop }
  ensure
    2.times { release << true }
    waiter&.join(1)
  end

  def test_shutdown_with_pending_trims_processes_all_queued_work
    started = Queue.new
    release = Queue.new
    processed = Queue.new

    pool = new_pool(0, 3) do
      started << true
      release.pop
      processed << true
    end

    request_size = 9
    request_size.times { |i| pool << i } # 3 threads busy, 6 items queued

    3.times { started.pop }

    assert_equal 3, pool.spawned

    shutdown_thread = Thread.new { pool.shutdown(-1) }
    wait_until { pool.trim_requested == 3 }

    6.times { release << true }
    wait_until { processed.size == 6 }

    assert_equal 3, pool.spawned

    3.times { release << true }
    shutdown_thread.join

    assert_equal request_size, processed.size
  ensure
    request_size.times { release << true }
  end

  def test_trim_thread_exit_hook
    exited = Queue.new
    options = {
      min_threads: 0,
      max_threads: 1,
      before_thread_exit: [
        {
          id: nil,
          block: proc { exited << 1 },
          cluster_only: false,
        }
      ]
    }
    block = proc { }
    pool = MutexPool.new("tst", options, &block)

    pool << 1

    assert_equal 1, pool.spawned

    # Thread.pass helps with intermittent tests, JRuby
    pool.trim
    Thread.pass
    sleep 0.1 unless Puma::IS_MRI # intermittent without
    assert_equal 0, pool.spawned
    Thread.pass
    sleep 0.1 unless Puma::IS_MRI # intermittent without
    assert_equal 1, exited.length
  end

  def test_autotrim
    pool = mutex_pool(1, 2)

    timeout = 0
    pool.auto_trim! timeout

    pool.<< [1, 2] do
      assert_equal 2, pool.spawned
    end

    start = Time.now
    Thread.pass until pool.spawned == 1 || Time.now - start > 1

    assert_equal 1, pool.spawned
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
    Thread.pass until pool.spawned == 0 || Time.now - start > 1

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

    # JRuby Array#<< is not thread-safe
    rescued = Queue.new
    pool = mutex_pool(2, 2, pool_shutdown_grace_time: grace) do
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

    pool.shutdown(timeout)

    assert_equal 0, pool.spawned
    assert_equal 2, rescued.length
    until rescued.empty?
      thread = rescued.pop
      refute thread.alive?
    end
  end

  def test_correct_waiting_count_for_killed_threads
    pool = new_pool(1, 1) { |_| }
    sleep 1

    # simulate our waiting processor thread getting killed for whatever reason
    pool.instance_eval { @processors[0].kill }
    sleep 1
    pool.reap
    sleep 1

    pool << 0
    sleep 1
    assert_equal 0, pool.backlog
  end

  def test_pool_capacity_never_negative
    pool = mutex_pool(5,5) do
      th = Thread.current
      Thread.new {th.join; pool.signal}
      th.kill
    end

    pool << 1
    pool << 1
    pool << 1
    pool << 1
    pool << 1

    assert_equal 5, pool.spawned

    pool.min = 1
    pool.max = 1

    assert_equal 0, pool.pool_capacity
  end

  def test_io_threads_allowed_over_the_limit
    mutex = Mutex.new
    mutex.lock
    queue = Queue.new
    concurrent_threads = []
    pool = new_pool(0, 4, max_io_threads: 4) do |processor, io_bound_thread|
      processor.mark_as_io_thread! if io_bound_thread
      queue << Thread.current
      mutex.synchronize { }
    end

    8.times do
      pool << true
      concurrent_threads << queue.pop
    end
    assert_equal 8, concurrent_threads.size
    refute_predicate pool, :can_spawn_processor?
  ensure
    mutex.unlock
    pool.shutdown(1)
  end

  def test_io_threads_over_the_limit_count_as_normal_threads
    mutex = Mutex.new
    mutex.lock
    queue = Queue.new
    concurrent_threads = []
    pool = new_pool(0, 2, max_io_threads: 2) do |processor, io_bound_thread|
      processor.mark_as_io_thread! if io_bound_thread
      queue << Thread.current
      mutex.synchronize { }
    end

    [true, true, true, false].each do |io_bound_thread|
      pool << io_bound_thread
      concurrent_threads << queue.pop
    end
    assert_equal 4, concurrent_threads.size
    refute_predicate pool, :can_spawn_processor?
  ensure
    mutex.unlock
    pool.shutdown(1)
  end

  def test_extra_io_threads_release_spawned_count_on_exit
    mutex = Mutex.new
    mutex.lock
    queue = Queue.new
    pool = new_pool(0, 2, max_io_threads: 2) do |processor, io_bound_thread|
      processor.mark_as_io_thread! if io_bound_thread
      queue << Thread.current
      mutex.synchronize { }
    end

    4.times { pool << true }
    4.times { queue.pop }
    assert_equal 4, pool.spawned

    mutex.unlock

    Timeout.timeout(1) { sleep 0.01 until pool.spawned == 2 }
    assert_equal 2, pool.spawned
    assert_equal 2, pool.pool_capacity
  ensure
    mutex.unlock if mutex.owned?
    pool.shutdown(1)
  end
end
