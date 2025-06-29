# frozen_string_literal: true

require_relative "../test_puma"

module TestPuma
  module ShutdownRequests
    # Perform a server shutdown while requests are pending (one in app handler on server, one still sending from client)
    def shutdown_requests(s1_complete: true, s1_response: nil, post: false, s2_response: nil, **options)
      mutex = Mutex.new
      app_finished = ConditionVariable.new

      server_run(**options) { |env|
        path = env["REQUEST_PATH"]
        mutex.synchronize do
          app_finished.signal
          app_finished.wait(mutex) if path == "/s1"
        end
        [204, {}, []]
      }

      pool = @server.instance_variable_get(:@thread_pool)

      # Trigger potential race condition by pausing Reactor#add until shutdown begins
      if options.fetch(:queue_requests, true)
        reactor = @server.instance_variable_get(:@reactor)
        reactor.instance_variable_set(:@pool, pool)
        reactor.instance_variable_set(:@force_shutdown_after, options[:force_shutdown_after])
        reactor.extend(Module.new do
          def add(client)
            if client.env["REQUEST_PATH"] == "/s2"
              fsa = @force_shutdown_after
              if fsa && fsa >= 0
                # Wait for force_shutdown, not just shutdown — on JRuby/TruffleRuby,
                # slow shutdown_debug logging can let s2 complete in between.
                Thread.pass until @pool.instance_variable_get(:@force_shutdown)
              else
                Thread.pass until @pool.instance_variable_get(:@shutdown)
              end
            end
            super
          end
        end)
      end

      s1 = nil
      s2 = send_http post ?
        "POST /s2 HTTP/1.1\r\nHost: test.com\r\nContent-Type: text/plain\r\nContent-Length: 5\r\n\r\nhi!" :
        "GET /s2 HTTP/1.1\r\n"
      mutex.synchronize do
        s1 = send_http "GET /s1 HTTP/1.1\r\n\r\n"
        app_finished.wait(mutex)
        app_finished.signal if s1_complete
      end

      @server.stop
      Thread.pass until pool.instance_variable_get(:@shutdown)

      if s1_response
        s1_result = begin
          s1.read_response.status
        rescue Errno::ECONNABORTED, Errno::ECONNRESET, EOFError, Timeout::Error
          nil
        end

        if !s1_result && options[:force_shutdown_after]
          assert_nil s1_result
        else
          assert_match s1_response, s1_result
        end
      end

      s2 << "\r\n"

      s2_result = begin
        s2.read_response.status
      rescue Errno::ECONNABORTED, Errno::ECONNRESET, EOFError
        post ? "408" : nil
      end

      if s2_response
        assert_match s2_response, s2_result
      else
        assert_nil s2_result
      end
    end
  end
end
