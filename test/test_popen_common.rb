# frozen_string_literal: true

module TestPOpenCommon

  def term_exit_code
    skip_unless_signal_exist? :TERM
    skip_unless :mri

    start_puma '-q test/rackup/hello.ru'
    _, status = stop_puma signal: :TERM

    sleep 0.2 # needed to allow bind & ctrl sockets to be closed
    assert_equal 15, status
  end

  def term_suppress
    skip_unless_signal_exist? :TERM
    setup_puma :tcp, config: 'raise_exception_on_sigterm false'
    start_puma '-q test/rackup/hello.ru'
    _, status = stop_puma signal: :TERM

    sleep 0.2
    assert_equal 0, status
  end

  def usr2_hot_restart_puma_and_listen(argv, log: false)
    start_puma argv

    connection = connect_get
    initial_reply = connection.read_body

    usr2_hot_restart_puma connection
    [initial_reply, connect_get_body]
  end

  # reuses an existing connection to make sure that works
  def usr2_hot_restart_puma(connection, log: false)
    @pids_stopped = []
    @pids_waited  = []
    if @ctrl_type
      cli_pumactl 'restart'
    else
      Process.kill :USR2, @pid
    end
    connection.get # trigger it to start by sending a new request
    wait_for_puma_to_boot log: log
  end

  def connections_restart(type: :USR2, threads: 10, clients_per_thread: 200,
      dly_client: 0.005, req_per_client: 1, body_kb: 10)
    if type == :USR2
      skip_if :jruby, suffix: <<-MSG
 - file descriptors are not preserved on exec on JRuby; connection reset errors are expected during restarts
      MSG
    end

    ctrl_type (Puma.windows? ? :tcp : :pid_file)

    replies = {}

    @config_path = tmp_path '.config', contents: 'persistent_timeout 5'
    @config_path_is_tmp = true

    start_puma '-q -t 5:5 test/rackup/ci_string.ru'

    replies[:phase0_pids] = get_worker_pids if workers

    time_start = Time.now.to_f

    client_threads = create_clients replies, threads, clients_per_thread,
      dly_client: dly_client, keep_alive: false,
      body_kb: body_kb, req_per_client: req_per_client

    sleep (@workers ? 0.7 : 1.0) # allow connections on phase 0

    is_usr1 = type == :USR1

    cli_pumactl (is_usr1 ? 'phased-restart' : 'restart')
    client_threads.each(&:join)
    time_end = Time.now.to_f

    # need to wait for single restarts before stopping
    unless workers
      assert_server_gets cmd_to_log_str(is_usr1 ? 'phased-restart' : 'restart')
    end

    replies[:restart_count] = 1

    ssl = @bind_type == :ssl
    old = RUBY_VERSION < '2.4'
    old_ssl = old && ssl

    # 'less than or equal' expected values
    lte_bad     = 0    # replies[:bad_response]
    lte_refused = 0    # replies[:refused]
    lte_reset   = 0    # replies[:reset]
    lte_timeout = 0    # replies[:timeout]
    lte_write   = 0    # replies[:refused_write]

    if Puma.windows?  #──────────────────────────────── Windows
      if type == :USR1
      else #──── :USR2
        lte_refused = old_ssl ? 4 : 2
        lte_reset   = replies[:restart_count] * threads
        lte_write   = ssl ? 10 : 5
      end
    elsif darwin?     #──────────────────────────────── Darwin
      if type == :USR1
        lte_refused = old_ssl ? 10 : (old ? 1 : (ssl ? 8 : 0))
        lte_reset   = (@workers || 1) * 3
        lte_timeout = 4
        lte_write   = old_ssl ?  6 : 2
      else #──── :USR2
        lte_refused = old_ssl ? 31 : (ssl ? 9 : 1)
        lte_reset   = 6
        lte_timeout = 1
        lte_write   = old_ssl ? 26 : (ssl ? 2 : 1) # last '1' may be old Rubies
      end
    else              #──────────────────────────────── Ubuntu
      if type == :USR1
        lte_refused = old_ssl ?  8 : (ssl ? 6 : 6)
        lte_write   = old_ssl ?  2 : 2   # 2 with aunix ?
      else #──── :USR2
        lte_refused = old_ssl ?  6 : (ssl ? 6 : 3)
        lte_write   = old_ssl ?  3 : 1
      end
        lte_reset   = 1
        lte_timeout = 1
    end

    if RUBY_ENGINE == 'truffleruby'
      lte_reset   = 10
      lte_timeout = 5
    end

    assert_operator replies[:refused], :<=, lte_refused,
      'Read refused errors'

    assert_operator replies[:reset]  , :<=, lte_reset,
      'Read reset errors'

    assert_operator replies[:timeout], :<=, lte_timeout,
      'Read timeout errors'

    assert_operator replies[:bad_response], :<=, lte_bad,
      'Read bad responses'

    assert_operator replies[:refused_write], :<=, lte_write,
      'Write refused errors'

    replies
  ensure
    if defined?(replies) && replies.is_a?(::Hash)
      msg = replies_info replies
      msg << format("  %5.2f Total Client Time\n", time_end - time_start)
      time_str = replies_time_info replies, threads, clients_per_thread, req_per_client
      $debugging_info << "\n#{full_name}\n#{msg}\n#{time_str}\n"
    end
  end

  # rubocop:disable Metrics/ParameterLists
  # the config file used 'test/config/shutdown.rb', is empty, but can be changed
  # for testing, etc
  def shutdown(command, threads:, clients_per_thread:,
    dly_thread:, dly_client:, dly_app:, cmd_wait:, req_per_client: 1,
    puma_threads: nil)

    replies = {}

    setup_puma config_path: 'test/config/shutdown.rb'

    puma_threads ||= '5:5'

    start_puma "-q -t #{puma_threads} test/rackup/ci_string.ru"

    client_threads = create_clients replies, threads, clients_per_thread,
      dly_thread: dly_thread, dly_client: dly_client, dly_app: dly_app,
      req_per_client: req_per_client

    sleep cmd_wait
    cli_pumactl command
    # use join timeout to see intermittent errors, some sockets seem to freeze?
    join_timeout =
      if Puma.windows?
        35
      elsif darwin?
        30
      else # Ubuntu
        10
      end

    client_threads.each { |t| t.join join_timeout }

    self.stopped = true
    @server = nil
    replies
  ensure
    time_str = replies_time_info replies, threads, clients_per_thread, req_per_client
    $debugging_info << "\n#{full_name}\n#{replies_info replies}\n#{time_str}\n"
  end

  private
    def darwin?
      RUBY_PLATFORM.include? 'darwin'
    end
end
