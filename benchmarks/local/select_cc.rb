# frozen_string_literal: true

require 'openssl'
require_relative 'bench_base'
require_relative 'puma_info'
require_relative '../../test/helpers/sockets'
require 'tmpdir'

module TestPuma

  # This file is meant to be run with `select_cc.sh`.  It starts a
  # Puma server, and uses `TestPuma::Sockets#request_stream` to send a user defined
  # number of requests to the server.  It does so for four response body sizes,
  # 1, 10, 100 and 2050 kB.  Within each size it sends requests with an array body,
  # a chunked body, and a string body.
  #
  # wrk does not support UNIXSockets, so part of the reason for this is to see
  # data on their performance.  Also, it should not be used to gauge 'requests per
  # second' (RPS), as it is not fast enough.  It should correctly show Puma's
  # response time for a reasonable stream of requests.
  #
  # It uses `test/rackup/ci_select.ru` for its rackup file.
  #
  # `cc_type_size_times.sh` arguments:
  #
  # Puma Server
  # ```
  # -s socket type, tcp, ssl, aunix, or unix
  # -t same as Puma --thread
  # -w same as Puma --worker
  # ```
  #
  # `TestPuma::Sockets#request_stream`
  # ```
  # -l loops/threads used
  # -c connections created serially
  # -r requests per connection
  # ```
  #
  # Example:
  # ```
  # benchmarks/local/select_cc.sh -l15 -c50 -r20 -s aunix -w2 -t5:5
  # ```
  # Starts Puma with '-w2 -t5:5' settings, binding to an abstract UNIXSocket.
  # Sends nine sets of 15,000 (15*50*20) requests (2050 kB body only uses 300
  # requests), and displays the timing info.
  #
  class SelectCC < BenchBase

    include TestPuma::Sockets

    def run
      @puma_info = PumaInfo.new ['-S', @state_file]

      @types = @body_conf && @body_conf.start_with?(*TYPES.map { |a| a.first.to_s }) ?
        TYPES.select { |a| a.first == @body_conf[0].to_sym } : TYPES

      @sizes = (size = @body_conf[/\d+\z/]) ? [size.to_i] : SIZES

      if @types.map(&:first).include? :i
        create_io_files
        # warm up - run files responses
        @sizes.each do |size|
          connection_threads = request_stream({}, 5, 1, dly_thread: @thread_dly,
            dly_client: @client_dly, body_conf: "i#{size}", req_per_client: 5)
            .each(&:join)
        end
      end

      @client_dly = 0.000_005
      @thread_dly = @client_dly/@thread_loops.to_f

      req_fmt = "%d requests - %d loops of %d clients * %d requests per client"
      @ttl_reqs = @thread_loops * @clients_per_thread * @req_per_client
      req_run_data = format(req_fmt, @ttl_reqs, @thread_loops, @clients_per_thread, @req_per_client)
      puts '', req_run_data

      @max_099_time = 0
      @max_050_time = 0
      @errors = false

      summaries = Hash.new { |h,k| h[k] = {} }

      @single_size = @sizes.length == 1
      @single_type = @types.length == 1

      line_width = 0

      @sizes.each do |size|
        if size == 2050
          @thread_loops = 10
          @clients_per_thread = 15
          @req_per_client = 2
          @ttl_reqs = @thread_loops * @clients_per_thread * @req_per_client
        end

        @types.each do |pre, desc|
          body_conf = "#{pre}#{size}"
          hsh = run_request_stream body_conf
          line_width += 6
          if line_width > 74
            STDOUT.write body_conf
            puts ''
            line_width = 0
          else
            STDOUT.write body_conf.ljust(6)
          end

          @errors ||= hsh[:success] != @ttl_reqs
          times = hsh[:times_summary]
          @max_099_time = times[0.99] if times[0.99] > @max_099_time
          @max_050_time = times[0.50] if times[0.50] > @max_050_time

          summaries[size][desc] = hsh
          sleep 0.5
        end
      end

      puts "\n\nRequest / Response time distribution in mS"

      run_summaries summaries

      overall_summary(summaries) unless @single_size || @single_type

      puts req_run_data
      env_log

    rescue => e
      puts e.class, e.message, e.backtrace
    ensure
      puts ''
      @puma_info.run 'stop'
      sleep 2
    end

    def run_summaries(summaries)
      fmt_vals = '%6s  %5d'.dup
      hdr = '       req/sec'.dup

      digits = [4 - Math.log10(@max_099_time).to_i, 3].min

      percentile = [0.1, 0.2, 0.4, 0.5, 0.6, 0.8, 0.9, 0.95, 0.97, 0.99]
      percentile.each { |n|
        fmt_vals << (digits < 0 ? " %6d" : " %6.#{digits}f")
        hdr << format(' %6s', "#{(100*n).to_i}% ")
      }

      label = @single_type ? 'Size' : 'Type'

      if @errors
        hdr << '  bad req'
        fmt_vals << '  %7d'
      end

      puts hdr
      @sizes.each do |size|
        puts format("#{'─' * 83}%5dkB", size) unless @single_type
        @types.each do |_, t_desc|
          desc = @single_type ? size : t_desc

          hsh = summaries[size][t_desc]

          hsh[:times_summary].delete 1.0

          if @errors
            errors = @ttl_reqs - hsh[:success]
            puts "#{format fmt_vals, desc, hsh[:rps], *hsh[:times_summary].values, errors}\n"
          else
            puts "#{format fmt_vals, desc, hsh[:rps], *hsh[:times_summary].values}\n"
          end
        end
      end
      puts '─' * 83
    end

    def overall_summary(summaries)
      digits = [4 - Math.log10(@max_050_time).to_i, 3].min
      puts "\n        ────────── req/sec ──────────   ────── req 50% times ────────",
             "Size    array   chunk  string      io   array   chunk  string      io"
      fmt_rps = '%6d  %6d  %6d  %6d'
      fmt_times = (digits < 0 ? "  %6d" : "  %6.#{digits}f")*4
      @sizes.each do |size|
        line = format '%-5d  ', size
        resp = ''
        line << format(fmt_rps, *@types.map { |_, t_desc| summaries[size][t_desc][:rps] })
        line << format(fmt_times, *@types.map { |_, t_desc| summaries[size][t_desc][:times_summary][0.5] })
        puts line
      end
      puts '─' * 69
    end

    def run_request_stream(body_conf)
      replies = {}
      t_st = Process.clock_gettime Process::CLOCK_MONOTONIC
      connection_threads = request_stream replies, @thread_loops, @clients_per_thread,
        dly_thread: @thread_dly, dly_client: @client_dly, body_conf: body_conf, req_per_client: @req_per_client

      connection_threads.each(&:join)
      ttl_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st

      close_clients

      replies[:rps] = replies[:times].length/ttl_time
      replies_time_info(replies, @thread_loops, @clients_per_thread, @req_per_client)
      replies
    end
  end
end
TestPuma::SelectCC.new.run
