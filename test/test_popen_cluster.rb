# frozen_string_literal: true

require_relative 'helpers/svr_popen'
require_relative 'test_popen_common.rb'

class TestPOpenCluster < ::TestPuma::SvrPOpen
  parallelize_me! if ::Puma.mri?

  include TestPOpenCommon

  def setup
    super
    workers 2
  end

  def teardown
    super unless skipped?
  end

  def test_usr2_hot_restart_ssl
    skip_unless :ssl
    setup_puma :ssl
    _, new_reply = usr2_hot_restart_puma_and_listen 'test/rackup/ci_string.ru'
    assert_includes new_reply, 'Hello World'
  end

  def test_usr2_hot_restart_tcp
    _, new_reply = usr2_hot_restart_puma_and_listen 'test/rackup/ci_string.ru'
    assert_includes new_reply, 'Hello World'
  end

  def test_connections_usr1_phased_restart_aunix
    skip_unless_signal_exist? :USR1
    skip_unless :aunix
    setup_puma :aunix
    ctrl_type :tcp
    replies = connections_restart type: :USR1

    assert_operator replies[:pids].keys.length, :>, workers,
      "Response pids should greater than workers (#{workers})"

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr1_phased_restart_ssl
    skip_unless :ssl
    skip_unless_signal_exist? :USR1
    setup_puma :ssl
    replies = connections_restart type: :USR1

    assert_operator replies[:pids].keys.length, :>, workers,
      "Response pids should greater than workers (#{workers})"

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr1_phased_restart_ssl_200kb_resp
    skip_unless :ssl
    skip_unless_signal_exist? :USR1
    setup_puma :ssl
    replies = connections_restart type: :USR1, body_kb: 200

    assert_operator replies[:pids].keys.length, :>, workers,
      "Response pids should greater than workers (#{workers})"

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr1_phased_restart_tcp
    skip_unless_signal_exist? :USR1
    replies = connections_restart type: :USR1

    assert_operator replies[:pids].keys.length, :>, workers,
      "Response pids should greater than workers (#{workers})"

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr1_phased_restart_unix
    skip_unless_signal_exist? :USR1
    setup_puma :unix
    ctrl_type :tcp
    replies = connections_restart type: :USR1

    assert_operator replies[:pids].keys.length, :>, workers,
      "Response pids should greater than workers (#{workers})"

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr1_phased_restart_fork_worker
    skip_unless_signal_exist? :USR1
    setup_puma :tcp, config: 'fork_worker'

    connections_restart type: :USR1

    assert_equal workers, get_worker_pids(1).length,
      "Phase 1 pids should equal #{workers}"
  end

  def test_connections_usr2_hot_restart_ssl
    skip_unless :ssl
    setup_puma :ssl
    ctrl_type :tcp
    replies = connections_restart type: :USR2

    unless DARWIN
      response_pids = workers * (replies[:restart_count] - 1)
      assert_operator replies[:pids].keys.length, :>=, response_pids,
        "Response pids should greater than or equal to #{response_pids}"
    end
  end

  def test_connections_usr2_hot_restart_tcp
    setup_puma :tcp
    ctrl_type :tcp
    replies = connections_restart type: :USR2

    response_pids = workers * (replies[:restart_count] - 1)
    assert_operator replies[:pids].keys.length, :>=, response_pids,
      "Response pids should greater than or equal to #{response_pids}"
  end

  def test_connections_usr2_hot_restart_unix
    setup_puma :unix
    ctrl_type :tcp
    replies = connections_restart type: :USR2

    response_pids = workers * (replies[:restart_count] - 1)
    assert_operator replies[:pids].keys.length, :>=, response_pids,
      "Response pids should greater than or equal to #{response_pids}"
  end

  def test_pre_existing_unix
    skip_unless :unix
    setup_puma :unix

    File.write @bind_path, 'pre existing', mode: 'wb'

    start_puma '-q test/rackup/ci_string.ru'

    stop_puma

    assert File.exist?(@bind_path)

  ensure
    if UNIX_SKT_EXIST
      # SvrPOpen's teardown assumes @bind_path is deleted, and asserts that
      File.unlink @bind_path if File.exist? @bind_path
    end
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    start_puma '-q test/rackup/ci_string.ru'
    worker_pids = get_worker_pids

    Process.kill :INFO, worker_pids.first

    assert_server_gets 'Thread: TID'
  end

  def test_shutdown_stop_tcp
    setup_puma :tcp
    ctrl_type :pid_file
    cluster_shutdown 'stop'
  end

  def test_shutdown_stop_tcp_threads_1
    setup_puma :tcp
    ctrl_type :pid_file
    cluster_shutdown 'stop', puma_threads: '1:1'
  end

  def test_shutdown_stop_unix
    setup_puma :unix
    ctrl_type :pid
    cluster_shutdown 'stop'
  end

  def test_shutdown_stop_sigterm_tcp
    setup_puma :tcp
    ctrl_type :pid_file
    cluster_shutdown 'stop-sigterm'
  end

  def test_shutdown_stop_sigterm_unix
    setup_puma :unix
    ctrl_type :pid
    cluster_shutdown 'stop-sigterm'
  end

  def test_stop_one_client
    ctrl_type :pid_file
    start_puma '-q -t 5:5 test/rackup/ci_string.ru'
    connect_get_response dly: 0.5
    cli_pumactl 'stop'

    begin
      Process.wait2 @pid
    rescue Errno::ECHILD
    end
    assert true
  end

  def test_term_exit_code
    term_exit_code
  end

  def test_term_suppress
    term_suppress
  end

  def test_worker_clean_exit_stop_tcp
    ctrl_type :tcp
    worker_clean_exit 'stop'
  end

  def test_worker_clean_exit_stop_pid
    ctrl_type :pid_file
    worker_clean_exit 'stop'
  end

  def test_worker_clean_exit_stop_sigterm_ctrl_tcp
    ctrl_type :tcp
    worker_clean_exit 'stop-sigterm'
  end

  def test_worker_clean_exit_stop_sigterm_ctrl_pid_file
    ctrl_type :pid_file
    worker_clean_exit 'stop-sigterm'
  end

  # mimicking stuck workers, test respawn with external TERM
  def test_stuck_external_term_spawn
    skip_unless_signal_exist? :SIGTERM

    worker_respawn(0) do |phase0_worker_pids|
      last = phase0_worker_pids.last
      # test is tricky if only one worker is TERM'd, so kill all but
      # spread out, so all aren't killed at once
      phase0_worker_pids.each do |pid|
        Process.kill :TERM, pid
        sleep 4 unless pid == last
      end
    end
  end

  # mimicking stuck workers, test restart
  def test_stuck_usr1_phased_restart
    skip_unless_signal_exist? :USR1
    worker_respawn { |phase0_worker_pids| Process.kill :USR1, @pid }
  end

  def test_worker_boot_timeout
    timeout = 1
    worker_timeout(timeout, 2, "worker failed to boot within \\\d+ seconds", "worker_boot_timeout #{timeout}; on_worker_boot { sleep #{timeout + 1} }")
  end

  def test_worker_timeout
    skip 'Thread#name not supported' unless Thread.current.respond_to?(:name)
    timeout = Puma::Const::WORKER_CHECK_INTERVAL + 1
    worker_timeout(timeout, 1, "worker failed to check in within \\\d+ seconds", <<RUBY)
worker_timeout #{timeout}
on_worker_boot do
  Thread.new do
    sleep 1
    Thread.list.find {|t| t.name == 'puma stat payload'}.kill
  end
end
RUBY
  end

  def test_worker_index_is_with_in_options_limit
    skip_unless_signal_exist? :SIGTERM
    workers nil # set in t3_conf.rb
    setup_puma config_path: 'test/config/t3_conf.rb'

    start_puma '-q test/rackup/ci_string.ru'

    get_worker_pids(0, 3) # this will wait till all the processes are up

    assert File.file?('t3-worker-2-pid')

    Process.kill :TERM, Integer(File.read 't3-worker-2-pid')

    worker_index_within_number_of_workers = !File.file?("t3-worker-3-pid")

    stop_puma Integer(File.read 't3-pid')

    File.unlink 't3-pid'          if File.file? 't3-pid'
    File.unlink 't3-worker-0-pid' if File.file? 't3-worker-0-pid'
    File.unlink 't3-worker-1-pid' if File.file? 't3-worker-1-pid'
    File.unlink 't3-worker-2-pid' if File.file? 't3-worker-2-pid'
    File.unlink 't3-worker-3-pid' if File.file? 't3-worker-3-pid'

    assert(worker_index_within_number_of_workers)
  end

  # use three workers to keep accepting clients
  def test_refork
    workers 3
    refork = Tempfile.new 'refork'
    setup_puma config: <<RUBY
fork_worker 20
on_refork { File.write '#{refork.path}', 'Reforked' }
RUBY
    ctrl_type :pid_file

    start_puma '-q test/rackup/ci_string.ru'

    pids = get_worker_pids 0

    socks = []
    until refork.read == 'Reforked'
      socks << connect_get(len: 1)
      sleep 0.004
    end

    100.times {
      socks << connect_get(len: 1)
      sleep 0.004
    }

    socks.each { |s| s.read_body }

    refute_includes pids, get_worker_pids(1, workers - 1)
  end

  def test_fork_worker_spawn
    workers nil
    setup_puma config: <<RUBY
workers 1
fork_worker 0
app do |_|
  pid = spawn('ls', [:out, :err]=>'/dev/null')
  sleep 0.01
  exitstatus = Process.detach(pid).value.exitstatus
  [200, {}, [exitstatus.to_s]]
end
RUBY
    ctrl_type :pid_file

    start_puma
    assert_equal '0', connect_get_body
  end

  def test_nakayoshi
    setup_puma config: 'nakayoshi_fork true'
    ctrl_type :pid_file

    start_puma '-q test/rackup/ci_string.ru'

    output = nil
    Timeout.timeout(10) do
      until output
        output = @server.gets[/Friendly fork preparation complete/]
        sleep 0.01
      end
    end

    assert output, "Friendly fork didn't run"
  end

  def test_prune_bundler_with_multiple_workers
    setup_puma config_path: 'test/config/prune_bundler_with_multiple_workers.rb'
    ctrl_type :pid_file
    start_puma
    body = connect_get_body

    assert body, "embedded app"
  end

  def test_load_path_includes_extra_deps
    setup_puma config_path: 'test/config/prune_bundler_with_deps.rb'
    ctrl_type :pid_file
    start_puma '-q test/rackup/ci_string.ru'

    load_path = []
    while (line = @server.gets) =~ /^LOAD_PATH/
      load_path << line.gsub(/^LOAD_PATH: /, '')
    end
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, load_path.last)
  end

  def test_load_path_does_not_include_nio4r
    setup_puma config_path: 'test/config/prune_bundler_with_deps.rb'
    ctrl_type :pid_file
    start_puma '-q test/rackup/ci_string.ru'

    load_path = []
    while (line = @server.gets) =~ /^LOAD_PATH/
      load_path << line.gsub(/^LOAD_PATH: /, '')
    end

    load_path.each do |path|
      refute_match(%r{gems/nio4r-[\d.]+/lib}, path)
    end
  end

  def test_json_gem_not_required_in_master_process
    setup_puma config_path: 'test/config/prune_bundler_print_json_defined.rb'
    ctrl_type :pid_file
    start_puma '-q test/rackup/ci_string.ru'

    line = @server.gets
    assert_match(/defined\?\(::JSON\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process
    start_puma "-w #{workers} -C test/config/prune_bundler_print_nio_defined.rb test/rackup/ci_string.ru"

    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_nio4r_gem_not_required_in_master_process_when_using_control_server
    ctrl_type :tcp
    start_puma "-C test/config/prune_bundler_print_nio_defined.rb test/rackup/ci_string.ru"

    line = @server.gets
    assert_match(/Starting control server/, line)

    line = @server.gets
    assert_match(/defined\?\(::NIO\): nil/, line)
  end

  def test_application_is_loaded_exactly_once_if_using_preload_app
    start_puma '-q --preload test/rackup/write_to_stdout_on_boot.ru'

    worker_load_count = 0
    worker_load_count += 1 while @server.gets =~ /^Loading app/

    assert_equal 0, worker_load_count
  end

  def test_warning_message_outputted_when_single_worker
    start_puma "-w 1 test/rackup/hello.ru", wait_for_boot: false

    assert_server_gets(/ ! WARNING: Detected running cluster mode with 1 worker/)
  end

  def test_warning_message_not_outputted_when_single_worker_silenced
    setup_puma config: "silence_single_worker_warning"

    start_puma "-w 1 test/rackup/hello.ru", wait_for_boot: false

    output = []
    while (line = @server.gets) && line !~ /Worker \d \(PID/
      output << line
    end

    refute_match(/WARNING: Detected running cluster mode with 1 worker/, output.join)
  end

  private

  def worker_clean_exit(cmd)
    start_puma '-q test/rackup/ci_string.ru'

    # Get the PIDs of the child workers.
    worker_pids = get_worker_pids

    cli_pumactl cmd
    sleep 0.5 # need time for child processes to close
    assert_server_gets cmd_to_log_str(cmd)

    zombies = bad_exit_pids worker_pids
    @server = nil
    assert_empty zombies, "Process ids #{zombies} became zombies"
  end

  def worker_timeout(timeout, iterations, details, config)
    setup_puma config: config
    ctrl_type :pid_file

    start_puma '-q -t 1:1 test/rackup/ci_string.ru'

    pids = []
    Timeout.timeout(iterations * timeout + 1) do
      (pids << @server.gets[/Terminating timed out worker \(#{details}\): (\d+)/, 1]).compact! while pids.size < workers * iterations
    end
    pids.map!(&:to_i)

    assert_equal pids, pids.uniq
  end

  def cluster_shutdown(cmd, puma_threads: nil)
    threads = 10
    clients_per_thread = 40
    req_per_client = 3

    replies = shutdown(cmd,
      threads: threads, clients_per_thread: clients_per_thread,
      dly_thread: 0.05, dly_client: nil, dly_app: 0.01,
      req_per_client: req_per_client, cmd_wait: 0.5, puma_threads: puma_threads
    )

    if DARWIN
      lte_refused = 20
      lte_resets  = 20
      lte_write = 1_000
    elsif cmd == 'stop-sigterm'
      lte_refused = 15
      lte_resets  = 20
      lte_write = 1_000
    else        # stop
      lte_refused = 15
      lte_resets  = 20
      lte_write = 1_000
    end

    assert_operator replies[:reset], :<=, lte_resets,
      'Read reset errors'
    assert_operator replies[:refused], :<=, lte_refused,
      'Read refused errors'

    assert_operator replies[:refused_write], :<=, lte_write,
      'Write refused errors'
  end

  def worker_respawn(phase = 1)
    threads = []
    rescue_err = DARWIN ? [IOError, Errno::ECONNRESET, Errno::EBADF] :
      [IOError, Errno::ECONNRESET]

    setup_puma config: 'worker_shutdown_timeout 2'

    start_puma '-q -t 1:1 test/rackup/ci_string.ru'

    # make sure two workers have booted
    phase0_worker_pids = get_worker_pids

    [35, 40].each do |sleep_time|
      threads << Thread.new do
        begin
          s = connect_get dly: sleep_time
          s.read_body 60
          # stuck connections will raise IOError or Errno::ECONNRESET
          # when shutdown
        rescue *rescue_err
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
    pids.map do |pid|
      begin
        pid if Process.kill 0, pid
      rescue Errno::ESRCH
        nil
      end
    end.compact
  end
end if ::Process.respond_to?(:fork)
