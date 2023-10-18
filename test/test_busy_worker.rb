# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_in_process"

class TestBusyWorker < TestPuma::ServerInProcess
  def setup
    skip_unless :mri # This feature only makes sense on MRI
  end

  def with_server(qty, **options)
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
        sleep 0.1
        [200, {}, [""]]
      ensure
        @mutex.synchronize do
          @requests_running -= 1
        end
      end
    end

    # we want more than one thread 'alive' when the requests are sent
    options[:min_threads] ||= 4
    options[:max_threads] ||= 4
    options[:log_writer]  ||= Puma::LogWriter.strings

    server_run app: request_handler, **options

    Array.new(qty) { send_http GET_10 }.each(&:read_response)

    assert_equal qty, @requests_count, "number of requests needs to match"
    assert_equal 0, @requests_running, "none of requests needs to be running"
  end

  # Multiple concurrent requests are not processed
  # sequentially as a small delay is introduced
  def test_multiple_requests_waiting_on_less_busy_worker
    n = 4
    with_server n, wait_for_less_busy_worker: 1.0

    assert_equal 1, @requests_max_running, "maximum number of concurrent requests needs to be 1"
  end

  # Multiple concurrent requests are processed
  # in parallel as a delay is disabled
  def test_multiple_requests_processing_in_parallel
    n = 4
    with_server n, wait_for_less_busy_worker: 0.0

    assert_equal n, @requests_max_running, "maximum number of concurrent requests needs to match"
  end
end
