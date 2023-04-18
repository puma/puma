require_relative "helper"
require_relative "helpers/puma_socket"

class TestBusyWorker < Minitest::Test
  parallelize_me! if ::Puma.mri?

  include PumaTest::PumaSocket

  def setup
    skip_unless :mri # This feature only makes sense on MRI

    @host = '127.0.0.1'
    @app = -> (env) {
      sleep 0.1
      [200, {}, ["Hello World"]]
    }

    @server = nil
  end

  def teardown
    return if skipped?
    @server&.stop true
  end

  def with_server(**options)
    @requests_count = 0 # number of requests processed
    @requests_running = 0 # current number of requests running
    @requests_max_running = 0 # max number of requests running in parallel
    @mutex = Mutex.new

    request_handler = ->(env) do
      @mutex.synchronize do
        @requests_count += 1
        @requests_running += 1
        if @requests_running > @requests_max_running
          @requests_max_running = @requests_running
        end
      end

      begin
        @app.call env
      ensure
        @mutex.synchronize do
          @requests_running -= 1
        end
      end
    end

    options[:min_threads] = 4
    options[:max_threads] = 4
    options[:log_writer] = log_writer ||= Puma::LogWriter.strings

    @server = Puma::Server.new request_handler, nil, **options
    @port = (@server.add_tcp_listener '127.0.0.1', 0).addr[1]
    @server.run
    # server is running in thread, and creating threads
    sleep 0.1 until @server.running == 4
  end

  def run_requests(n)
    # send all requests first, read later
    skts = Array.new(n) {
      max_retries = 5
      retries = 0
      begin
        send_http "GET / HTTP/1.0\r\n\r\n"
      rescue Errno::ECONNREFUSED => e
        retries += 1
        if retries < max_retries
          retry
        else
          flunk "TestBusyWorker#run_requests failed via #{e.class}"
        end
      end
    }

    Array.new(n) do |i|
      # using read_body seems to intermittently fail
      Thread.new { skts[i].sysread 1_024 }
    end.each(&:join)
  end

  # Multiple concurrent requests are not processed
  # sequentially as a small delay is introduced
  def test_multiple_requests_waiting_on_less_busy_worker
    with_server(wait_for_less_busy_worker: 1.0)
    n = 4
    run_requests n

    assert_equal n, @requests_count, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
    assert_equal 1, @requests_max_running, "maximum number of concurrent requests needs to be 1"
  end

  # Multiple concurrent requests are processed
  # in parallel as a delay is disabled
  def test_multiple_requests_processing_in_parallel
    with_server(wait_for_less_busy_worker: 0.0)
    n = 4
    run_requests n

    assert_equal n, @requests_count, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
    assert_equal n, @requests_max_running, "maximum number of concurrent requests needs to match"
  end
end
