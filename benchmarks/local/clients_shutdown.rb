# frozen_string_literal: true

=begin
bundle exec ruby -Ilib bin/puma -t1:1 -w10 -b tcp://127.0.0.1:40010 -C ./benchmarks/local/drain_on_shutdown.ru --control-url=tcp://127.0.0.1:40001 --control-token=test test/rackup/ci_string.ru

ruby ./benchmarks/local/clients_shutdown.rb 10 1 10 2.0 tcp
=end


require_relative '../../test/helpers/sockets'
require_relative 'clients_base'

module TestPuma
  class ClientsShutdown < ClientsBase

    include TestPuma::Sockets

    def run
      client_dly = 0.0005
      thread_dly = client_dly/thread_loops.to_f

      replies = {}
      t_st = Time.now
      client_threads = create_clients replies, thread_loops, thread_connections,
        dly_thread: thread_dly, dly_client: client_dly,
        body_kb: body_kb, req_per_client: req_per_client, dly_app: dly_app

      client_threads.each(&:join)
      ttl_time = Time.now - t_st

      puts replies_info(replies)

      info = format("%4dkB Response Body, Total Time %5.2f", (body_kb || 10), ttl_time)
      puts info, replies_time_info(replies, thread_loops, thread_connections, req_per_client), '', ''

      replies = {}
      t_st = Time.now

      client_threads = create_clients replies, thread_loops, thread_connections,
        dly_thread: thread_dly, dly_client: client_dly,
        body_kb: body_kb, req_per_client: req_per_client, dly_app: dly_app

      sleep 0.1
      connect_raw "GET /stop?token=test HTTP/1.0\r\n\r\n", type: :tcp, p: 40010

      client_threads.each(&:join)
      ttl_time = Time.now - t_st

      puts replies_info(replies)

      info = format("%4dkB Response Body, Total Time %5.2f", (body_kb || 10), ttl_time)
      puts info, replies_time_info(replies, thread_loops, thread_connections, req_per_client)
    end
  end
end

TestPuma::ClientsShutdown.new.run
