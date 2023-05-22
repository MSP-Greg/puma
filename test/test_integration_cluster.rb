# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

require "time"

class TestIntegrationCluster < TestIntegration
  parallelize_me! if ::Puma::IS_MRI && ::Puma::HAS_FORK

  def workers ; 2 ; end

  def setup
    skip_unless :fork
    super
  end

  def teardown
    return if skipped?
    super
  end

  def test_hot_restart_does_not_drop_connections_threads
    hot_restart_does_not_drop_connections num_threads: 10, total_requests: 3_000
  end

  def test_hot_restart_does_not_drop_connections
    hot_restart_does_not_drop_connections num_threads: 1, total_requests: 1_000
  end

  def test_pre_existing_unix
    skip_unless :unix

    @bind_path = tmp_path '.bind'

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{workers} -q test/rackup/sleep_step.ru", unix: :unix

    stop_server

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_pre_existing_unix_stop_after_restart
    skip_unless :unix

    @bind_path = tmp_path '.bind'

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-w #{workers} -t1:5 -q test/rackup/sleep_step.ru", unix: :unix
    connection = connect unix: true
    restart_server connection

    stop_server

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server "-w #{workers} -q test/rackup/hello.ru"
    worker_pids = get_worker_pids

    Process.kill :INFO, worker_pids.first
    assert wait_for_server_to_include("Thread: TID")
  end

  def test_usr2_restart
    _, new_reply = restart_server_and_listen("-q -w #{workers} test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # Next two tests, one tcp, one unix
  # Send requests 10 per second.  Send 10, then :TERM server, then send another 30.
  # No more than 10 should throw Errno::ECONNRESET.

  def test_term_closes_listeners_tcp
    skip_unless_signal_exist? :TERM
    term_closes_listeners unix: false
  end

  def test_term_closes_listeners_unix
    skip_unless_signal_exist? :TERM
    term_closes_listeners unix: true
  end

  # Next two tests, one tcp, one unix
  # Send requests 1 per second.  Send 1, then :USR1 server, then send another 24.
  # All should be responded to, and at least three workers should be used

  def test_usr1_all_respond_tcp
    skip_unless_signal_exist? :USR1
    usr1_all_respond unix: false
  end

  def test_usr1_fork_worker
    skip_unless_signal_exist? :USR1
    usr1_all_respond config: '--fork-worker'
  end

  def test_usr1_all_respond_unix
    skip_unless_signal_exist? :USR1
    usr1_all_respond unix: true
  end

  def test_term_exit_code
    cli_server "-w #{workers} test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_term_suppress
    cli_server "-w #{workers} -C test/config/suppress_exception.rb test/rackup/hello.ru"

    _, status = stop_server

    assert_equal 0, status
  end

  def test_on_booted
    cli_server "-w #{workers} -C test/config/event_on_booted.rb -C test/config/event_on_booted_exit.rb test/rackup/hello.ru", no_wait: true

    assert wait_for_server_to_include "on_booted called"
  end

  def test_term_worker_clean_exit
    cli_server "-w #{workers} test/rackup/hello.ru"

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    # Signal the workers to terminate, and wait for them to die.
    Process.kill :TERM, @pid
    Process.wait @pid

    zombies = bad_exit_pids worker_pids

    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  # mimicking stuck workers, test respawn with external TERM
  def test_stuck_external_term_spawn
    skip_unless_signal_exist? :TERM

    worker_respawn(0) do |phase0_worker_pids|
      # test is tricky if only one worker is TERM'd, so kill all but
      # spread out, so all aren't killed at once
      phase0_worker_pids.each do |pid|
        Process.kill :TERM, pid
        Process.wait(pid, Process::WNOHANG) rescue nil
      end
    end
  end

  # mimicking stuck workers, test restart
  def test_stuck_phased_restart
    skip_unless_signal_exist? :USR1
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  def test_worker_check_interval
    # iso8601 2022-12-14T00:05:49Z
    re_8601 = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/
    worker_check_interval = 1

    cli_server "-w1 -t1:1 #{set_pumactl_args} test/rackup/hello.ru", config: "worker_check_interval #{worker_check_interval}"

    sleep worker_check_interval + 1
    checkin_1 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_1
    last_checkin_1 = Time.parse checkin_1

    sleep worker_check_interval + 1
    checkin_2 = get_stats["worker_status"].first["last_checkin"]
    assert_match re_8601, checkin_2
    last_checkin_2 = Time.parse checkin_2

    assert(last_checkin_2 > last_checkin_1)
  end

  def test_worker_boot_timeout
    timeout = 1
    worker_timeout(timeout, 2, "worker failed to boot within \\\d+ seconds", "worker_boot_timeout #{timeout}; on_worker_boot { sleep #{timeout + 1} }")
  end

  def test_worker_timeout
    skip 'Thread#name not available' unless Thread.current.respond_to?(:name)
    timeout = Puma::Configuration::DEFAULTS[:worker_check_interval] + 1
    worker_timeout(timeout, 1, "worker failed to check in within \\\d+ seconds", <<~RUBY)
      worker_timeout #{timeout}
      on_worker_boot do
        Thread.new do
          sleep 1
          Thread.list.find {|t| t.name == 'puma stat pld'}.kill
        end
      end
    RUBY
  end

  def test_worker_index_is_with_in_options_limit
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/t3_conf.rb test/rackup/hello.ru"

    get_worker_pids(0, 3) # this will wait till all the processes are up

    worker_pid_was_present = File.file? "t3-worker-2-pid"

    stop_server(Integer(File.read("t3-worker-2-pid")))

    worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

    stop_server(Integer(File.read("t3-pid")))

    assert(worker_pid_was_present)
    assert(worker_index_within_number_of_workers)
  ensure
    File.unlink "t3-pid" if File.file? "t3-pid"
    File.unlink "t3-worker-0-pid" if File.file? "t3-worker-0-pid"
    File.unlink "t3-worker-1-pid" if File.file? "t3-worker-1-pid"
    File.unlink "t3-worker-2-pid" if File.file? "t3-worker-2-pid"
    File.unlink "t3-worker-3-pid" if File.file? "t3-worker-3-pid"
  end

  # use three workers to keep accepting clients
  def test_fork_worker_on_refork
    refork = Tempfile.create(['', 'refork'], PUMA_TMPDIR)
    refork_path = refork.path
    wrkrs = 3

    cli_server "-w #{wrkrs} -t2:5 test/rackup/hello_with_delay.ru", config: <<~RUBY
      fork_worker 20
      on_refork { File.write '#{refork_path}', 'Reforked' }
    RUBY

    pids = get_worker_pids 0, wrkrs

    socks = []
    until refork.read == 'Reforked'
      socks << fast_connect
      sleep 0.004
    end

    100.times {
      socks << fast_connect
      sleep 0.004
    }

    results = Array.new socks.length
    until socks.compact.empty?
      socks.each_with_index do |sock, idx|
        next if sock.nil?
        if sock.wait_readable 0.000_5
          begin
            results[idx] = read_body sock
          rescue StandardError => e
            results[idx] = e.class
          end
          socks[idx] = nil
        end
      end
    end

    assert_equal ['Hello World'], results.uniq

    refute_includes pids, get_worker_pids(1, wrkrs - 1)
  ensure
    refork&.close unless refork&.closed?
    File.unlink refork_path if File.exist? refork_path
  end

  def test_fork_worker_spawn
    cli_server '', config: <<~RUBY
      workers 1
      fork_worker 0
      app do |_|
        pid = spawn('ls', [:out, :err]=>'/dev/null')
        sleep 0.01
        exitstatus = Process.detach(pid).value.exitstatus
        [200, {}, [exitstatus.to_s]]
      end
    RUBY

    assert_equal '0', read_body(connect)
  end

  def test_prune_bundler_with_multiple_workers
    cli_server "-C test/config/prune_bundler_with_multiple_workers.rb"
    reply = read_body(connect)

    assert reply, "embedded app"
  end

  def test_load_path_includes_extra_deps
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    load_path = []

    while @server.wait_readable 3
      line = @server.gets
      if line.start_with? 'LOAD_PATH: '
        load_path << line.sub('LOAD_PATH: ', '')
      else
        break
      end
    end
    assert_match(%r{gems/minitest-[\d.]+/lib$}, load_path.last)
  end

  def test_load_path_does_not_include_nio4r
    cli_server "-w #{workers} -C test/config/prune_bundler_with_deps.rb test/rackup/hello.ru"

    load_path = []

    while @server.wait_readable 3
      line = @server.gets
      if line.start_with? 'LOAD_PATH: '
        load_path << line.sub('LOAD_PATH: ', '')
      else
        break
      end
    end

    load_path.each do |path|
      refute_match(%r{gems/nio4r-[\d.]+/lib}, path)
    end
  end

  def test_json_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_json_defined.rb test/rackup/hello.ru"

    @server.wait_readable 3
    line = @server.gets
    assert_match(/defined\?\(::JSON\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process
    cli_server "-w #{workers} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    @server.wait_readable 3
    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process_when_using_control_server
    cli_server "-w #{workers} #{set_pumactl_args} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/hello.ru"

    @server.wait_readable 3
    line = @server.gets
    assert_match(/Starting control server/, line)

    @server.wait_readable 3
    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_application_is_loaded_exactly_once_if_using_preload_app
    cli_server "-w #{workers} --preload test/rackup/write_to_stdout_on_boot.ru", no_wait: true

    assert wait_for_server_to_match(/^Loading app/)
    refute wait_for_server_to_match(/^Loading app/, ret_false_re: /Worker 1 \(PID:/)
  end

  def test_warning_message_outputted_when_single_worker
    cli_server "-w 1 test/rackup/hello.ru"

    assert wait_for_server_to_include('WARNING: Detected running cluster mode with 1 worker')
  end

  def test_warning_message_not_outputted_when_single_worker_silenced
    cli_server "-w 1 test/rackup/hello.ru", config: "silence_single_worker_warning"

    refute wait_for_server_to_match(/WARNING: Detected running cluster mode with 1 worker/m,
      ret_false_re: /Worker \d \(PID/)
  end

  def test_signal_ttin
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)
  end

  def test_signal_ttou
    cli_server "-w 2 test/rackup/hello.ru"
    get_worker_pids # to consume server logs

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 1 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_youngest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :youngest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest
    cli_server "-w 2 test/rackup/hello.ru", config: "worker_culling_strategy :oldest"
    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    assert wait_for_server_to_match(/Worker 2 \(PID: \d+\) booted in/)

    Process.kill :TTOU, @pid

    assert wait_for_server_to_match(/Worker 0 \(PID: \d+\) terminating/)
  end

  def test_culling_strategy_oldest_fork_worker
    cli_server "-w 2 test/rackup/hello.ru", config: <<~RUBY
      worker_culling_strategy :oldest
      fork_worker
    RUBY

    get_worker_pids # to consume server logs

    Process.kill :TTIN, @pid

    @server.wait_readable 3
    line = @server.gets
    assert_match(/Worker 2 \(PID: \d+\) booted in/, line)

    Process.kill :TTOU, @pid

    @server.wait_readable 3
    line = @server.gets
    assert_match(/Worker 1 \(PID: \d+\) terminating/, line)
  end

  def test_hook_data
    skip_unless_signal_exist? :TERM

    file0 = 'hook_data-0.txt'
    file1 = 'hook_data-1.txt'

    cli_server "-C test/config/hook_data.rb test/rackup/hello.ru"
    get_worker_pids 0, 2
    stop_server

    # helpful for non MRI Rubies, may hang on MRI Rubies
    assert(wait_for_server_to_include 'puma shutdown') unless Puma::IS_MRI

    assert_equal 'index 0 data 0', File.read(file0, mode: 'rb:UTF-8')
    assert_equal 'index 1 data 1', File.read(file1, mode: 'rb:UTF-8')

  ensure
    File.unlink file0 if File.file? file0
    File.unlink file1 if File.file? file1
  end

  def test_puma_debug_loaded_exts
    cli_server "-w #{workers} test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions - worker 0:')
    assert wait_for_server_to_include('Loaded Extensions - master:')
  end

  private

  def worker_timeout(timeout, iterations, details, config)
    cli_server "-w #{workers} -t 1:1 test/rackup/hello.ru", config: config

    pids = []
    time_limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + (iterations * timeout + 1)
    ok = true
    wanted_size = workers * iterations
    while pids.size < wanted_size
      if @server.wait_readable 0.1
        (pids << @server.gets[/Terminating timed out worker \(#{details}\): (\d+)/, 1]).compact!
      end
      sleep 0.1
      if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_limit
        ok = false
        break
      end
    end
    assert ok, "Failed within #{iterations * timeout + 1} seconds, terminated workers #{pids.size}"
    pids.map!(&:to_i)

    assert_equal pids, pids.uniq
  end

  # Send requests 20 per second.  Send 20, then :TERM server, then send another 20.
  # All reuqests have a one second delay in the app.
  # No more than 10 should throw Errno::ECONNRESET.
  def term_closes_listeners(unix: false)
    skipped = true
    skip_unless_signal_exist? :TERM
    skipped = false

    msg = ''
    cli_server "-w #{workers} -t 5:5 -q test/rackup/sleep_pid.ru", unix: unix
    replies = []
    req_interval = 0.05
    sleep_time = 1
    mutex = Mutex.new
    req_queue = Thread::Queue.new
    req_errors  = Hash.new 0
    resp_errors = Hash.new 0
    requests = 40

    req_refused = unix ? Errno::ENOENT : Errno::ECONNREFUSED

    req_thread = Thread.new do
      req_str = "sleep#{sleep_time}"
      requests.times.each do |i|
        sleep req_interval
        begin
          req_queue << [i, fast_connect(req_str, unix: unix)]
          if i == 20
            Process.kill :TERM, @pid
          end
        rescue req_refused
          mutex.synchronize { replies[i] = :req_refused }
        rescue Errno::ECONNRESET
          mutex.synchronize { replies[i] = :req_reset   }
        rescue => e
          req_errors[e.class] += 1
          mutex.synchronize { replies[i] = :req_failure }
        end
      end
    end

    resp_reset = DARWIN && unix ? EOFError : Errno::ECONNRESET

    resp_thread = Thread.new do
      while (skt_info = req_queue.pop)
        resp_status replies, resp_reset, resp_errors, skt_info, mutex
        break if req_queue.empty? && req_queue.closed?
      end
    end

    req_thread.join
    req_queue.close
    resp_thread.join

    resp_bodies = replies.grep String

    resp_info = replies.grep(Symbol).uniq.sort.map { |n| [n, replies.count(n)] }.to_h
    resp_info.default_proc = proc { |_, _| 0 }

    req_refused   = resp_info[:req_refused]
    req_reset     = resp_info[:req_reset]
    req_failures  = req_errors.values.sum
    successes     = resp_bodies.length
    resp_resets   = resp_info[:resp_reset]
    resp_failures = resp_errors.values.sum
    resp_timeouts = resp_info[:resp_timeout]

    r_success = replies.rindex { |e| e.is_a? String }
    l_reset   = replies.index  :resp_reset
    l_failure = replies.index  :resp_failure

    msg = +"Writes: #{req_refused} refused, #{req_reset} reset, #{req_failures} failures\n" \
          " Reads: #{successes} successes, #{resp_resets} resets, #{resp_failures} failed, #{resp_timeouts} timeouts"

    unless resp_failures.zero?
      msg << "\n#{resp_errors.inspect}"
    end

    assert_equal 0, req_failures , "Req Errors #{req_errors.inspect}"
    assert_equal 0, resp_timeouts, msg
    assert_equal 0, resp_failures, msg

    assert_operator 10, :<=, successes    , msg
    assert_operator 20, :>=, req_refused  , msg
    assert_operator 2 , :>=, req_reset     , msg
    assert_operator 15, :>=, resp_resets  , msg

    # Interleaved asserts
    if l_reset
      assert_operator r_success, :<, l_reset  , "Interleaved success and reset"
    elsif l_failure
      assert_operator r_success, :<, l_failure, "Interleaved success and refused"
    end

  ensure
    unless skipped
      if passed?
        $debugging_info << "#{full_name}\n    #{msg.gsub "\n", "\n    "}\n"
      elsif msg.empty?
        $debugging_info << "#{full_name}\n    Unknown Error\n"
      else
        $debugging_info << "#{full_name}\n    #{msg.gsub "\n", "\n    "}\n#{replies.inspect}\n"
      end
    end
  end

  # Send requests 20 per second.  Send 20, then :USR1 server, then send another 20.
  # All should be responded to, and at least three workers should be used
  def usr1_all_respond(unix: false, config: '')
    msg = ''
    cli_server "-w #{workers} -t 5:5 -q test/rackup/sleep_pid.ru #{config}", unix: unix
    replies = []
    req_interval = 0.05
    sleep_time = 1
    mutex = Mutex.new
    req_queue = Thread::Queue.new
    req_errors  = Hash.new 0
    resp_errors = Hash.new 0
    requests = 40

    req_refused = unix ? Errno::ENOENT : Errno::ECONNREFUSED

    req_thread = Thread.new do
      req_str = "sleep#{sleep_time}"
      requests.times.each do |i|
        sleep req_interval
        begin
          req_queue << [i, fast_connect(req_str, unix: unix)]
          if i == 20
            Process.kill :USR1, @pid
          end
        rescue req_refused
          mutex.synchronize { replies[i] = :req_refused }
        rescue Errno::ECONNRESET
          mutex.synchronize { replies[i] = :req_reset   }
        rescue => e
          req_errors[e.class] += 1
        end
      end
    end

    resp_reset = DARWIN && unix ? EOFError : Errno::ECONNRESET

    resp_thread = Thread.new do
      while (skt_info = req_queue.pop)
        resp_status replies, resp_reset, resp_errors, skt_info, mutex
        break if req_queue.empty? && req_queue.closed?
      end
    end

    req_thread.join
    req_queue.close
    resp_thread.join

    resp_bodies = replies.grep String

    resp_info = replies.grep(Symbol).uniq.sort.map { |n| [n, replies.count(n)] }.to_h
    resp_info.default_proc = proc { |_, _| 0 }

    req_refused   = resp_info[:req_refused]
    req_reset     = resp_info[:req_reset]
    req_failures  = req_errors.values.sum
    successes     = resp_bodies.length
    resp_resets   = resp_info[:resp_reset]
    resp_failures = resp_info[:resp_failure]
    resp_timeouts = resp_info[:resp_timeout]

    # get pids from replies, generate uniq array
    t = resp_bodies.map { |body| body[/\d+\z/] }
    qty_pids = t.uniq.compact.length

    msg = +"Writes: #{req_refused} refused, #{req_reset} reset, #{req_failures} failures\n" \
          " Reads: #{successes} successes, #{qty_pids} pids, #{resp_resets} resets, #{resp_failures} failed, #{resp_timeouts} timeouts"

    unless resp_failures.zero?
      msg << "\n#{resp_errors.inspect}"
    end

    assert_operator qty_pids, :>, 2, msg

    assert_equal 0, resp_resets  , msg
    assert_equal 0, resp_failures, msg
    assert_equal 0, resp_timeouts, msg

    assert_equal requests, successes, msg

    msg = "Reads: #{requests} requests, #{successes} successes, #{qty_pids} pids"

  ensure
    if msg.empty?
      $debugging_info << "#{full_name}\n    Unknown Error\n"
    else
      $debugging_info << "#{full_name}\n    #{msg.gsub "\n", "\n    "}\n"
    end
  end

  def worker_respawn(phase = 1, size = workers)
    threads = []

    cli_server "-w #{workers} -t 1:1 -C test/config/worker_shutdown_timeout_2.rb test/rackup/sleep_pid.ru"

    # make sure two workers have booted
    phase0_worker_pids = get_worker_pids

    [35, 40].each do |sleep_time|
      threads << Thread.new do
        begin
          connect "sleep#{sleep_time}"
          # stuck connections will raise IOError or Errno::ECONNRESET
          # when shutdown
        rescue IOError, Errno::ECONNRESET
        end
      end
    end

    @start_time = Time.now.to_f

    # below should 'cancel' the phase 0 workers, either via phased_restart or
    # externally TERM'ing them
    yield phase0_worker_pids

    # wait for new workers to boot
    phase1_worker_pids = get_worker_pids phase

    # should be empty if all phase 0 workers cleanly exited
    phase0_exited = bad_exit_pids phase0_worker_pids

    # Since 35 is the shorter of the two requests, server should restart
    # and cancel both requests
    assert_operator (Time.now.to_f - @start_time).round(2), :<, 35

    msg = "phase0_worker_pids #{phase0_worker_pids.inspect}  phase1_worker_pids #{phase1_worker_pids.inspect}  phase0_exited #{phase0_exited.inspect}"
    assert_equal workers, phase0_worker_pids.length, msg

    assert_equal workers, phase1_worker_pids.length, msg
    assert_empty phase0_worker_pids & phase1_worker_pids, "#{msg}\nBoth workers should be replaced with new"

    assert_empty phase0_exited, msg

    threads.each { |th| Thread.kill th }
  end

  # Returns an array of pids still in the process table, so it should
  # be empty for a clean exit.
  # Process.kill should raise the Errno::ESRCH exception, indicating the
  # process is dead and has been reaped.
  def bad_exit_pids(pids)
    t = pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end
    t.compact!; t
  end

  # reads response and loads 'replies' array with body or error info
  def resp_status(replies, resp_reset, resp_errors, skt_info, mutex)
    i, skt = skt_info
    begin
      body = read_body skt
      mutex.synchronize { replies[i] = body }
    rescue resp_reset
      # connection was accepted but then closed
      # client would see an empty response
      mutex.synchronize { replies[i] = :resp_reset }
    rescue Timeout::Error
      mutex.synchronize { replies[i] = :resp_timeout }
    rescue => e
      resp_errors[e.class] += 1
      mutex.synchronize { replies[i] = :resp_failure }
    end
  end
end if ::Process.respond_to?(:fork)
