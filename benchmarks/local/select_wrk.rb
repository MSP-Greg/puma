# frozen_string_literal: true

require_relative 'bench_base'
require_relative 'puma_info'

module TestPuma

  # This file is meant to be run with `overload_wrk.sh`.  It only works
  # with workers, and it uses smem and @ioquatix's fork of wrk, available at:
  # https://github.com/ioquatix/wrk
  #
  # It starts a Puma server, then runs 5 sets of wrk, with varying threads and
  # connections.  The first set has the thread count equal to total Puma thread
  # count, then four more are run with increasing thread count, ending with three
  # times the intial value.  After each run, Puma stats and smem info are retrieved.
  # Information is logged to the console, summarized, and also returned as a Ruby
  # object, so it may be used for CI.
  #
  # Puma stats includes the request count per worker.  The output shows a column
  # labelled 'spread'.  If `ary` is the array of worker request counts -
  # ```ruby
  # spread = 100 * (ary.max - ary.min)/ary.average
  # ```
  #
  # `overload_wrk.sh` arguments
  #
  # Puma Server
  # ```
  # -R rackup file, defaults to ci_string.ru
  # -s socket type, tcp or ssl, no unix with wrk
  # -t same as Puma --thread
  # -w same as Puma --worker
  # -C same as Puma --config
  # -b body type/size in kB, defaults to 10
  # -d app delay in seconds, defaults to 0
  # ```
  # wrk cmd
  # ```
  # -c wrk connection count per thread, defaults to 2
  # -T wrk time/duration, defaults to 10
  # ```
  #
  # Examples
  #
  # runs wrk a response body size of 10kB, 2 connections per wrk thread, and a
  # wrk duration of 10 sec, using a File object for the response body.
  # ```
  # benchmarks/local/select_wrk.sh -b10 -c1 -T10 -s tcp -w2 -t5:5
  # ```
  #
  class SelectWrk < BenchBase

    def run
      @puma_info = PumaInfo.new ['-S', @state_file]

      max_threads = @threads[/\d+\z/]

      @wrk_time ||= 10
      @thread_loops ||= (0.5 * (@workers || 1) * (max_threads || 5).to_i).to_i
      connections = @thread_loops * (@clients_per_thread || 2)

      @types = @body_conf && @body_conf.start_with?(*TYPES.map { |a| a.first.to_s }) ?
        TYPES.select { |a| a.first == @body_conf[0].to_sym } : TYPES

      @sizes = (s = @body_conf[/\d+\z/]) ? [s.to_i] : SIZES

      warm_up

      @max_100_time = 0
      @max_050_time = 0
      @errors = false

      summaries = Hash.new { |h,k| h[k] = {} }

      @single_size = @sizes.length == 1
      @single_type = @types.length == 1

      @sizes.each do |size|
        @types.each do |pre, desc|
          header = @single_size ? "-H '#{HDR_BODY_CONF}#{pre}#{size}'" :
            "-H '#{HDR_BODY_CONF}#{pre}#{size}'".ljust(21)

          # warmup?
          if pre == :i
            wrk_cmd = %Q[wrk -t#{@thread_loops} -c#{connections} -d1s --latency #{header} #{@wrk_bind_str}]
            %x[#{wrk_cmd}]
          end

          wrk_cmd = %Q[wrk -t#{@thread_loops} -c#{connections} -d#{@wrk_time}s --latency #{header} #{@wrk_bind_str}]
          hsh = run_wrk_parse wrk_cmd

          @errors ||= hsh.key? :errors

          times = hsh[:times]
          @max_100_time = times[1.0] if times[1.0] > @max_100_time
          @max_050_time = times[0.5] if times[0.5] > @max_050_time
          summaries[size][desc] = hsh

          @puma_info.run 'gc'
          sleep 2.0
        end
      end

      run_summaries summaries

      overall_summary(summaries) unless @single_size || @single_type

      puts "wrk -t#{@thread_loops} -c#{connections} -d#{@wrk_time}s"

      env_log

    rescue => e
      puts e.class, e.message, e.backtrace
    ensure
      puts ''
      @puma_info.run 'stop'
      sleep 2
    end

    def run_summaries(summaries)
      digits = [4 - Math.log10(@max_100_time).to_i, 3].min

      fmt_vals = "%-6s %6d".dup
      fmt_vals << (digits < 0 ? "  %6d" : "  %6.#{digits}f")*5
      fmt_vals << '  %8d'

      label = @single_type ? 'Size' : 'Type'

      if @errors
        puts "\n#{label}   req/sec    50%     75%     90%     99%    100%  Resp Size  Errors"
        desc_width = 83
      else
        puts "\n#{label}   req/sec    50%     75%     90%     99%    100%  Resp Size"
        desc_width = 65
      end

      puts format("#{'─' * desc_width} %s", @types[0][1]) if @single_type

      @sizes.each do |size|
        puts format("#{'─' * desc_width}%5dkB", size) unless @single_type
        @types.each do |_, t_desc|
          hsh = summaries[size][t_desc]
          times = hsh[:times].values
          desc = @single_type ? size : t_desc
          puts format(fmt_vals, desc, hsh[:rps], *times, hsh[:read]/hsh[:requests])
        end
      end

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
        line << format(fmt_times, *@types.map { |_, t_desc| summaries[size][t_desc][:times][0.5] })
        puts line
      end
      puts '─' * 69
    end

    def warm_up
      puts 'warm-up'
      if @types.map(&:first).include? :i
        create_io_files

        # get size files cached
        if @types.include? :i
          2.times do
            @sizes.each do |size|
              fn = format "#{Dir.tmpdir}/body_io_%04d.txt", size
              t = File.read fn, mode: 'rb'
            end
          end
        end
      end

      size = @sizes.length == 1 ? @sizes.first : 10

      @types.each do |pre, _|
        header = "-H '#{HDR_BODY_CONF}#{pre}#{size}'".ljust(21)
        warm_up_cmd = %Q[wrk -t2 -c4 -d1s --latency #{header} #{@wrk_bind_str}]
        run_wrk_parse warm_up_cmd
      end
      puts ''
    end

    # Experimental - try to see how busy a CI system is.
    def ci_test_rps
      host = ENV['HOST']
      port = ENV['PORT'].to_i

      str = 'a' * 65_500

      server = TCPServer.new host, port

      svr_th = Thread.new do
        loop do
          begin
            Thread.new(server.accept) do |client|
              client.sysread 65_536
              client.syswrite str
              client.close
            end
          rescue => e
            break
          end
        end
      end

      threads = []

      t_st = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      100.times do
        threads << Thread.new do
          100.times {
            s = TCPSocket.new host, port
            s.syswrite str
            s.sysread 65_536
            s = nil
          }
        end
      end

      threads.each(&:join)
      loops_time = (1_000*(Process.clock_gettime(Process::CLOCK_MONOTONIC) - t_st)).to_i

      threads.clear
      threads = nil

      server.close
      svr_th.join

      req_limit =
        if    loops_time > 3_050 then 13_000
        elsif loops_time > 2_900 then 13_500
        elsif loops_time > 2_500 then 14_000
        elsif loops_time > 2_200 then 18_000
        elsif loops_time > 2_100 then 19_000
        elsif loops_time > 1_900 then 20_000
        elsif loops_time > 1_800 then 21_000
        elsif loops_time > 1_600 then 22_500
        else                          23_000
        end
        [req_limit, loops_time]
    end

    def puts(*ary)
      ary.each { |s| STDOUT.syswrite "#{s}\n" }
    end
  end
end
TestPuma::SelectWrk.new.run
