# frozen_string_literal: true

java_import java.util.concurrent.ThreadPoolExecutor
java_import java.lang.Runnable

# From https://github.com/ruby-concurrency/concurrent-ruby/blob/d11b29c37b81320ca7126cc9cd85f4f3d17a78a3/lib/concurrent/executor/java_thread_pool_executor.rb#L111-L117
pool = java.util.concurrent.ThreadPoolExecutor.new(
    2,
    2,
    60,
    java.util.concurrent.TimeUnit::SECONDS,
    java.util.concurrent.LinkedBlockingQueue.new,
    java.util.concurrent.ThreadPoolExecutor::AbortPolicy.new
  )

# From concurrent-ruby: https://github.com/ruby-concurrency/concurrent-ruby/blob/d11b29c37b81320ca7126cc9cd85f4f3d17a78a3/lib/concurrent/executor/java_executor_service.rb#L77-L87
class Job
  include Runnable
  def initialize(args, block)
    @args = args
    @block = block
  end

  def run
    @block.call(*@args)
  end
end

2.times do
  pool.submit Job.new(nil, proc { sleep })
end

at_exit do
  # Request threadpool shutdown.
  pool.shutdown
  # Add two seconds wait to let the threads finish and then kill the threads.
  deadline = Time.now + 2
  while true
    break if pool.get_active_count.zero?
    if Time.now > deadline
      pool.shutdownNow
      break
    end
  end
end

run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
