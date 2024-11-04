require_relative "helper"
require_relative "helpers/test_puma/puma_socket"

class TestBusyWorker < Minitest::Test

  include ::TestPuma::PumaSocket

  def setup
    skip_unless :mri # This feature only makes sense on MRI
    @server = nil
  end

  def teardown
    return if skipped?
    @server&.stop true
  end

  def with_server(**options, &app)
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
        yield(env)
      ensure
        @mutex.synchronize do
          @requests_running -= 1
        end
      end
    end

    options[:min_threads] ||= 1
    options[:max_threads] ||= 10
    options[:log_writer]  ||= Puma::LogWriter.strings

    @server = Puma::Server.new request_handler, nil, **options
    @bind_port = (@server.add_tcp_listener '127.0.0.1', 0).addr[1]
    @server.run
  end

  # Multiple concurrent requests are not processed
  # sequentially as a small delay is introduced
  def test_multiple_requests_waiting_on_less_busy_worker
    with_server(wait_for_less_busy_worker: 1.0, workers: 2) do |_|
      sleep(0.1)

      [200, {}, [""]]
    end

    n = 2

    sockets = send_http_array GET_10, n

    read_response_array(sockets)

    assert_equal n, @requests_count, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
    assert_equal 1, @requests_max_running, "maximum number of concurrent requests needs to be 1"
  end

  # Multiple concurrent requests are processed
  # in parallel as a delay is disabled
  def test_multiple_requests_processing_in_parallel
    with_server(wait_for_less_busy_worker: 0.0, workers: 2) do |_|
      sleep(0.1)

      [200, {}, [""]]
    end

    n = 4

    sockets = send_http_array GET_10, n

    read_response_array(sockets)

    assert_equal n, @requests_count, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
    assert_equal n, @requests_max_running, "maximum number of concurrent requests needs to match"
  end

  def test_not_wait_for_less_busy_worker
    with_server do
      [200, {}, [""]]
    end

    assert_not_called_on_instance_of(Puma::ThreadPool, :wait_for_less_busy_worker) do
      send_http_read_response "GET / HTTP/1.0\r\n\r\n"
    end
  end

  def test_wait_for_less_busy_worker
    with_server(workers: 2) do
      [200, {}, [""]]
    end

    assert_called_on_instance_of(Puma::ThreadPool, :wait_for_less_busy_worker) do
      send_http_read_response "GET / HTTP/1.0\r\n\r\n"
    end
  end
end
