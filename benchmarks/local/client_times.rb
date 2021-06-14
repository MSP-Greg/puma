# frozen_string_literal: true

require_relative '../../test/helpers/sockets'
require_relative 'clients_base'

require 'optparse'

module TestPuma
  class ClientTimes < ClientsBase

    include TestPuma::Sockets

    def run
      client_dly = 0.000_01
      # client_dly = 0.001

      thread_dly = client_dly/@thread_loops.to_f

      replies = {}
      t_st = Time.now
      client_threads = create_clients replies, @thread_loops, @clients_per_thread,
        req_per_client: @req_per_client, dly_thread: thread_dly,
        dly_client: client_dly, body_kb: @body_kb, dly_app: @dly_app

      client_threads.each(&:join)
      ttl_time = Time.now - t_st

      rps = replies[:times].length/ttl_time
      info = format("%4dkB Response Body, Total Time %5.2f, RPS %d", @body_kb, ttl_time, rps)
      puts info, replies_time_info(replies, @thread_loops, @clients_per_thread, @req_per_client)

      close_clients
    end
  end
end
TestPuma::ClientTimes.new.run
