# frozen_string_literal: true

require_relative 'helpers/svr_popen'
require_relative 'test_popen_common.rb'

class TestPOpenSingle < ::TestPuma::SvrPOpen
#  parallelize_me! if ::Puma.mri?

  include TestPOpenCommon

  OSX_TRUFFLE = DARWIN && TRUFFLE

  def test_connections_usr2_hot_restart_ssl
    skip_unless :ssl
    setup_puma :ssl
    connections_restart type: :USR2, threads: 5, clients_per_thread: (OSX_TRUFFLE ? 50 : 200)
  end

  def test_connections_usr2_hot_restart_tcp
    connections_restart type: :USR2, threads: 5, clients_per_thread: (OSX_TRUFFLE ? 50 : 200)
  end

  def test_connections_usr2_hot_restart_unix
    skip_unless :unix
    setup_puma :unix
    connections_restart type: :USR2, threads: 5, clients_per_thread: (OSX_TRUFFLE ? 50 : 200)
  end

  def test_usr2_hot_restart
    ctrl_type (Puma.windows? ? :tcp : :pid)
    _, new_reply = usr2_hot_restart_puma_and_listen 'test/rackup/ci_string.ru'
    assert_includes new_reply, 'Hello World'
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_hot_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby

    ctrl_type (Puma.windows? ? :tcp : :pid)

    initial_reply, new_reply = usr2_hot_restart_puma_and_listen 'test/rackup/hello-env.ru'

    assert_includes initial_reply, 'Hello RAND'
    assert_includes new_reply, 'Hello RAND'
    refute_equal initial_reply, new_reply
  end

  def test_term_exit_code
    term_exit_code
  end

  def test_term_suppress
    term_suppress
  end

  def test_prefer_rackup_file_specified_by_cli
    setup_puma config: "rackup 'test/rackup/hello-env.ru'"
    ctrl_type (Puma.windows? ? :tcp : :pid)

    start_puma '-q test/rackup/ci_string.ru'

    assert_includes connect_get_body, 'Hello World'
  end

  def test_shutdown_stop_tcp
    setup_puma :tcp
    ctrl_type Puma.windows? ? :tcp : :pid
    single_shutdown :stop
  end

  def test_shutdown_stop_unix
    skip_unless :unix
    setup_puma :unix
    ctrl_type Puma.windows? ? :tcp : :pid
    single_shutdown :stop
  end

  def test_shutdown_stop_sig_term_tcp
    setup_puma :tcp
    ctrl_type Puma.windows? ? :tcp : :pid
    single_shutdown 'stop-sigterm'
  end

  def test_term_responds_to_10_sec_requests
    skip_if :jruby
    skip 'Skipped on Windows Ruby < 2.4.0, Ruby bug' if windows? && RUBY_VERSION < '2.4.0'

    ctrl_type(Puma.windows? ? :tcp : :pid)

    threads = 5
    clients_per_thread = 1
    req_per_client = 2
    replies = {}

    start_puma '-q -t 5:5 test/rackup/ci_string.ru'

    client_threads = create_clients replies, threads, clients_per_thread,
      dly_app: 10, req_per_client: req_per_client, resp_timeout: 15

    sleep 0.2

    #Process.kill :TERM, @pid
    cli_pumactl 'stop-sigterm'
    assert_server_gets 'Gracefully stopping' # wait for server to begin shutdown

    assert_raises (Errno::ECONNREFUSED) { connect_get_body }

    client_threads.each(&:join)

    assert_operator replies[:times].length, :>=, threads * clients_per_thread

    Process.wait @server.pid
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_int_refuse
    skip_if :jruby  # seems to intermittently lockup JRuby CI
    ctrl_type(:tcp) if Puma.windows?

    start_puma '-q test/rackup/ci_string.ru'
    begin
      connect.close
    rescue => ex
      fail "Port didn't open properly: #{ex.message}"
    end

    if Puma.windows?
      stop_puma
    else
      stop_puma signal: :INT
    end

    assert_raises(Errno::ECONNREFUSED) { connect }
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    start_puma '-q test/rackup/ci_string.ru'
    Process.kill :INFO, @pid
    assert_server_gets 'Thread: TID'
  end

  def test_write_to_log
    setup_puma config: <<RUBY
log_requests
stdout_redirect 't1-stdout'
RUBY
    tmp_paths << 't1-stdout'

    ctrl_type :tcp

    start_puma 'test/rackup/ci_string.ru'

    connect_get_response

    stop_puma wait_for_stop: false
    sleep 1 if Puma.windows?
    log = File.read 't1-stdout', mode: 'rb'

    assert_match %r!GET / HTTP/1\.1!, log
  end

  def test_puma_started_log_writing
    setup_puma config: <<RUBY
log_requests
stdout_redirect 't2-stdout'
RUBY

    tmp_paths << 't2-stdout'

    ctrl_type :tcp

    start_puma 'test/rackup/ci_string.ru'

    connect_get_response

    out = cli_pumactl('status').read

    stop_puma wait_for_stop: false
    sleep 1 if Puma.windows?
    log = File.read 't2-stdout'

    assert_match %r!GET / HTTP/1\.1!, log
    assert_equal "Puma is started\n", out

    refute File.file?('t2-pid')
  end

  def test_application_logs_are_flushed_on_write
    ctrl_type :tcp
    start_puma 'test/rackup/write_to_stdout.ru'
    connect_get_body

    log_line = @server.gets
    assert_equal "hello\n", log_line
  end

  private

  def single_shutdown(command)

    threads = Puma::IS_WINDOWS || Puma::IS_OSX && Puma::IS_MRI ? 5 : 10
    clients_per_thread = 40
    req_per_client = 3

    cmd_wait = 1.5

    replies = shutdown(command,
      threads: threads, clients_per_thread: clients_per_thread,
      dly_thread: 0.01, dly_client: nil, dly_app: 0.02,
      req_per_client: req_per_client, cmd_wait: cmd_wait
    )

    lte_resets  = 1
    lte_refused = 0
    lte_refused_write = 300

    if RUBY_ENGINE == 'truffleruby'
      lte_refused = 5
      lte_resets  = 5
    elsif Puma::IS_JRUBY
      lte_refused = 10
      lte_resets  = 10
    elsif Puma::IS_WINDOWS
      lte_resets  = 5
    elsif Puma::IS_OSX
      lte_refused = 2
      lte_resets  = 2
    elsif RUBY_VERSION < '2.3'  # must be Ubuntu MRI
      lte_refused = 1
    end

    assert_operator replies[:reset], :<=, lte_resets,
      'Read reset errors'
    assert_operator replies[:refused], :<=, lte_refused,
      'Read refused errors'
    if Puma::IS_MRI
      assert_operator replies[:refused_write], :<=, lte_refused_write,
        'Write refused errors'
    end
  end
end
