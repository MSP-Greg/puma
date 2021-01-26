# frozen_string_literal: true

require_relative '../../test/helpers/sockets'

$LOAD_PATH.unshift File.absolute_path('../../lib', __dir__)

require 'puma/control_cli'

module TestPuma
  class TestClients

    include TestPuma::Sockets

    def run
      thread_connections = ARGV[0].to_i
      thread_loops = ARGV[1].to_i
      @bind_type = ARGV[2].to_sym
      body_kb = ARGV[3].to_i
      keep_alive = ARGV[4] == 'true'
      req_per_client = ARGV[5].to_i

      memory_start = memory

      @ios_to_close = []

      case @bind_type
      when :ssl, :tcp
        @bind_port = 40010
      when :unix
        @bind_path = "#{Dir.home}/skt.unix"
      else
        exit 1
      end

      dly_client = 0.0005
      dly_thread = dly_client/thread_loops.to_f

      replies = {}
      t_st = Time.now

      client_threads = create_clients replies, thread_loops, thread_connections,
        dly_thread: dly_thread, dly_client: dly_client, body_kb: body_kb,
        keep_alive: keep_alive, req_per_client: req_per_client

      client_threads.each(&:join)
      ttl_time = Time.now - t_st

      memory_end = memory

      close_clients

      reqs = thread_loops * thread_connections * req_per_client
      rps = reqs/ttl_time
      info = format("%4dkB Response Body, Total Time %5.2f, RPS %d", body_kb, ttl_time, rps)
      puts info
      if replies[:times].compact.length < 20
        puts "Not enough connections for time info"
      else
        puts replies_time_info(replies, thread_loops, thread_connections, req_per_client)
      end

      puts '',
        '─────────────────────────────────── Memory before clients',
        memory_start, '',
        "─────────────────────────────────── Memory with #{thread_loops * thread_connections} open clients",
        memory_end, ''
    end

    def close_clients
      closed = 0
      @ios_to_close.each do |socket|
        if socket && socket.to_io.is_a?(IO) && !socket.closed?
          begin
            if @bind_type == :ssl
              socket.sysclose
            else
              socket.close
            end
            closed += 1
          rescue Errno::EBADF
          end
        end
      end
      puts "Closed #{closed} clients"
    end

    def memory
      cli_pumactl 'gc'
      `ps -eo pid,vsz,rss,comm`
    end

    def cli_pumactl(arg, log_cmd: false)
      args = %W[-C tcp://127.0.0.1:40001 -T test]

      args << arg if arg

      r, w = IO.pipe
      ::Puma::ControlCLI.new(args, w, w, allow_exit: false).run
      sleep 1
      w.close
      r.close
    end
  end
end

TestPuma::TestClients.new.run
