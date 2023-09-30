require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me! if ::Puma.mri?

  def workers ; 0 ; end

  def test_hot_restart_does_not_drop_connections_threads
    ttl_reqs = Puma.windows? ? 500 : 1_000
    hot_restart_does_not_drop_connections num_threads: 5, total_requests: ttl_reqs
  end

  def test_hot_restart_does_not_drop_connections
    if Puma.windows?
      hot_restart_does_not_drop_connections total_requests: 300
    else
      hot_restart_does_not_drop_connections
    end
  end

  def test_usr2_restart
    skip_unless_signal_exist? :USR2
    _, new_reply = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", new_reply
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby
    skip_unless_signal_exist? :USR2

    initial_reply, new_reply = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes initial_reply, "Hello RAND"
    assert_includes new_reply, "Hello RAND"
    refute_equal initial_reply, new_reply
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM
    skip_if :jruby # JVM does not return correct exit code for TERM

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_on_booted
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/event_on_booted.rb -C test/config/event_on_booted_exit.rb test/rackup/hello.ru",
      no_wait: true

    assert wait_for_server_to_include('on_booted called')
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 0, status
  end

  def test_rack_url_scheme_default
    skip_unless_signal_exist? :TERM

    cli_server("test/rackup/url_scheme.ru")

    body = send_http_read_resp_body
    stop_server

    assert_match("http", body)
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    skip_unless_signal_exist? :TERM

    cli_server("-C test/config/rack_url_scheme.rb test/rackup/url_scheme.ru")

    body = send_http_read_resp_body
    stop_server

    assert_match("https", body)
  end

  def test_prefer_rackup_file_specified_by_cli
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/with_rackup_from_dsl.rb test/rackup/hello.ru"
    body = send_http_read_resp_body
    stop_server

    assert_match("Hello World", body)
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    resp_sleep = 8

    cli_server 'test/rackup/sleep.ru'

    accepted_socket = send_http "GET /sleep#{resp_sleep} HTTP/1.1\r\n\r\n"
    sleep 0.1 # Ruby 2.7 ?
    Process.kill :TERM, @pid
    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    # listeners are closed after 'Gracefully stopping' is logged
    sleep 0.5

    # Invoke a request which must be rejected, need some time after shutdown
    assert_raises(Errno::ECONNREFUSED) { send_http_read_resp_body }

    assert_includes accepted_socket.read_body, "Slept #{resp_sleep}"
  ensure
    return unless @server
    Process.wait(@server.pid) if @server&.pid
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    skip_if :jruby  # seems to intermittently lockup JRuby CI

    cli_server 'test/rackup/hello.ru'
    begin
      send_http.close
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    Process.wait @pid

    assert_raises(Errno::ECONNREFUSED) { new_socket }
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server 'test/rackup/hello.ru'
    output = []
    t = Thread.new { output << @server.readlines }
    Process.kill :INFO, @pid
    Process.kill :INT , @pid
    t.join

    assert_match "Thread: TID", output.join
  end

  def test_write_to_log
    skip_unless_signal_exist? :TERM

    cli_server 'test/rackup/hello.ru', config: <<~CONFIG
      log_requests
      stdout_redirect "t1-stdout"
      pidfile "t1-pid"
    CONFIG

    2.times { send_http_read_response }

    `#{BASE} bin/pumactl  -P t1-pid status`
    sleep 1.5
    stop_server

    assert File.file?('t1-stdout'), "File 't1-stdout' does not exist"
    log = File.read('t1-stdout')
    assert_includes(log, "GET / HTTP/1.1")
    refute File.file?("t1-pid")
  ensure
    File.unlink 't1-stdout' if File.file? 't1-stdout'
    File.unlink 't1-pid'    if File.file? 't1-pid'
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    cli_server 'test/rackup/hello.ru', config: <<~CONFIG
      log_requests
      stdout_redirect "t2-stdout"
      pidfile "t2-pid"
    CONFIG

    2.times { send_http_read_resp_body }

    out = `#{BASE} bin/pumactl  -P t2-pid status`
    sleep 1.5
    stop_server
    assert File.file?('t2-stdout'), "File 't2-stdout' does not exist"
    log = File.read('t2-stdout')

    assert_includes(log, "GET / HTTP/1.1")
    assert_equal("Puma is started\n", out)
    refute File.file?("t2-pid")
  ensure
    File.unlink 't2-stdout' if File.file? 't2-stdout'
    File.unlink 't2-pid'    if File.file? 't2-pid'
  end

  def test_application_logs_are_flushed_on_write
    cli_server "#{set_pumactl_args} test/rackup/write_to_stdout.ru"

    send_http_read_resp_body

    cli_pumactl 'stop'

    assert wait_for_server_to_include("hello\n")
    assert wait_for_server_to_include('Goodbye')

    @server.close unless @server.closed?
    @server = nil
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/close_listeners.ru", merge_err: true
    if Puma::IS_JRUBY
      assert_includes send_http_read_response, "HTTP/1.1 500 Internal Server"
    else
      assert_includes send_http_read_response, "Found 1 TCPServer"
    end

    begin
      Timeout.timeout(5) do
        begin
          Process.kill :SIGTERM, @pid
        rescue Errno::ESRCH
        end
        begin
          Process.wait2 @pid
        rescue Errno::ECHILD
        end
      end
    rescue Timeout::Error
      Process.kill :SIGKILL, @pid
      assert false, "Process froze"
    end
    assert true
  end

  def test_puma_debug_loaded_exts
    cli_server "#{set_pumactl_args} test/rackup/hello.ru", puma_debug: true

    assert wait_for_server_to_include('Loaded Extensions:')

    cli_pumactl 'stop'
    assert wait_for_server_to_include('Goodbye')
    @server.close unless @server.closed?
    @server = nil
  end

  def test_idle_timeout
    cli_server "test/rackup/hello.ru", config: "idle_timeout 1"

    send_http

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end
  end

  def test_pre_existing_unix_after_idle_timeout
    skip_unless :unix

    File.open(@bind_path, mode: 'wb') { |f| f.puts 'pre existing' }

    cli_server "-q test/rackup/hello.ru", unix: :unix, config: "idle_timeout 1"

    socket = send_http

    sleep 1.15

    assert socket.wait_readable(1), 'Unexpected timeout'
    assert_raises Puma.jruby? ? IOError : Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end

    assert File.exist?(@bind_path)
  ensure
    if UNIX_SKT_EXIST
      File.unlink @bind_path if File.exist? @bind_path
    end
  end
end
