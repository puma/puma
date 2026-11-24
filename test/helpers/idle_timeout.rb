# frozen_string_literal: true

class TestIntegration
  def assert_idle_timeout_with_active_requests(worker_count)
    gate = TCPServer.new(HOST, 0)
    @ios_to_close << gate
    ports = Array.new(worker_count) { UniquePort.call }
    config = <<~CONFIG
      idle_timeout 1
      worker_shutdown_timeout 1
      threads 1, 1
      before_worker_boot { |index| $idle_worker_index = index }
      # Dedicated listeners make worker selection deterministic.
      Puma::Server.prepend(Module.new do
        define_method(:run) do |*args|
          add_tcp_listener('#{HOST}', #{ports.inspect}[$idle_worker_index || 0])
          super(*args)
        end
      end)
      app do |env|
        barrier = TCPSocket.new('#{HOST}', #{gate.addr[1]})
        barrier.puts Process.pid
        barrier.gets
        barrier.close
        [200, {'content-length' => '2'}, ['ok']]
      end
    CONFIG
    cli_server "-w #{worker_count == 1 ? 0 : worker_count}", config: config
    get_worker_pids(0, worker_count) if worker_count > 1

    clients = []
    barriers = []
    pids = []
    ports.each do |port|
      client = TCPSocket.new(HOST, port)
      @ios_to_close << client
      clients << client
      client << "GET / HTTP/1.0\r\n\r\n"
      assert gate.wait_readable(5), 'request must enter the application'
      barrier = gate.accept
      @ios_to_close << barrier
      barriers << barrier
      pids << barrier.gets.to_i
      # The other worker must have time to report idle repeatedly.
      sleep 2.2
    end
    assert_equal worker_count, pids.uniq.size
    probe = TCPSocket.new(HOST, ports.first)
    probe.close
    barriers.first.puts 'release'
    assert_includes clients.first.read, '200 OK'
    # Keep worker two busy after worker one has become idle.
    if worker_count > 1
      sleep 2.2
      barriers.last.puts 'release'
      assert_includes clients.last.read, '200 OK'
    end
    message = worker_count > 1 ? '- All workers reached idle timeout' : '- Idle timeout reached'
    assert wait_for_server_to_include(message)
    wait_server
  ensure
    barriers&.each { |barrier| barrier.puts('release') rescue nil }
  end
end
