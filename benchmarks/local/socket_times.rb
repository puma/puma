# frozen_string_literal: true

require_relative '../../test/helpers/sockets'

module TestPuma
  class TestClients

    include TestPuma::Sockets

    def run
      thread_loops = ARGV[0].to_i
      thread_connections = ARGV[1].to_i
      req_per_client = ARGV[2].to_i
      @bind_type = ARGV[3].to_sym
      body_kb = ARGV[4].to_i

      @ios_to_close = []

      case @bind_type
      when :ssl, :tcp
        @bind_port = 40010
      when :unix
        @bind_path = "#{Dir.home}/skt.unix"
      else
        exit 1
      end

      client_dly = 0.000_01
      thread_dly = client_dly/thread_loops.to_f

      replies = {}
      t_st = Process.clock_gettime Process::CLOCK_MONOTONIC
      client_threads = create_clients replies, thread_loops, thread_connections,
        dly_thread: thread_dly, dly_client: client_dly, body_kb: body_kb, req_per_client: req_per_client

      client_threads.each(&:join)
      ttl_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st

      rps = replies[:times].length/ttl_time
      info = format("%4dkB Response Body, Total Time %5.2f, RPS %d", body_kb, ttl_time, rps)
      puts info, time_info(thread_loops, thread_connections, replies[:times], req_per_client)

      unless replies[:times].length == thread_loops * thread_connections * req_per_client
        puts '', msg_from_replies(replies)
      end
    end
  end
end
TestPuma::TestClients.new.run
