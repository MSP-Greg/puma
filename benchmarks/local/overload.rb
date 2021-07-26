# frozen_string_literal: true

require_relative '../../test/helpers/sockets'
require_relative 'clients_base'

require 'optparse'

module TestPuma
  class OverloadTimes < ClientsBase

    include TestPuma::Sockets

    MULTS = [
      1,
      1.316074013,
      1.732050808,
      2.279507057,
      3
    ]

    def run
      client_dly = 0.000_01
      # client_dly = 0.001

      threads = @threads * @workers

      temp = MULTS.map { |m| (m * threads).round }

      ttl_connections = threads * @clients_per_thread

      loops_clients = temp.map { |m| [m, (ttl_connections/m.to_f).round] }

      # warm up
      replies = {}
      loops, clients = loops_clients[0][0], loops_clients[0][1]
      thread_dly = client_dly/loops.to_f
      client_threads = create_clients replies, loops, clients,
        req_per_client: @req_per_client, dly_thread: thread_dly,
        dly_client: client_dly, body_kb: @body_kb, dly_app: @dly_app
      client_threads.each(&:join)

      loops_clients.each do |loops,clients|
        thread_dly = client_dly/loops.to_f

        replies = {}
        t_st = Time.now
        client_threads = create_clients replies, loops, clients,
          req_per_client: @req_per_client, dly_thread: thread_dly,
          dly_client: client_dly, body_kb: @body_kb, dly_app: @dly_app

        client_threads.each(&:join)
        ttl_time = Time.now - t_st

        rps = replies[:times].length/ttl_time
        info = format("%4dkB Response Body, Total Time %5.2f, RPS %d", @body_kb, ttl_time, rps)
        puts info, replies_time_info(replies, loops, clients, @req_per_client)

        close_clients
      end
    end
  end
end
TestPuma::OverloadTimes.new.run
