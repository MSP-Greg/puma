# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle_1 < TestIntegration
  parallelize_me! if ::Puma::IS_MRI || (::Puma::IS_LINUX && !::Puma::IS_MRI)

  def workers ; 0 ; end

  def test_hot_restart_does_not_drop_connections_threads
    ttl_reqs = Puma.windows? ? 400 : 1_000
    hot_restart_does_not_drop_connections num_threads: 5, total_requests: ttl_reqs
  end

  def test_hot_restart_does_not_drop_connections
    if Puma.windows?
      hot_restart_does_not_drop_connections total_requests: 200
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
    skip_unless :mri # non MRI platforms return nil for TERM exit code

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 15, status
  end

  def test_on_booted
    skip_unless_signal_exist? :TERM
    cli_server "-C test/config/event_on_booted.rb -C test/config/event_on_booted_exit.rb test/rackup/hello.ru",
      no_wait: true

    assert wait_for_server_to_include "first on_booted called"
    assert wait_for_server_to_include "second on_booted called"
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM
    skip_unless :mri # non MRI platforms return nil for TERM exit code

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    send_http_read_response

    _, status = stop_server

    assert_equal 0, status
  end

  def test_rack_url_scheme_default
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/url_scheme.ru"

    body = send_http_read_resp_body
    stop_server

    assert_equal 'http', body
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    cli_server "#{set_pumactl_args} -C test/config/rack_url_scheme.rb test/rackup/url_scheme.ru"

    body = send_http_read_resp_body

    assert_equal 'https', body
  end

  def test_prefer_rackup_file_specified_by_cli
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/with_rackup_from_dsl.rb test/rackup/hello.ru"
    body = send_http_read_resp_body
    stop_server

    assert_equal 'Hello World', body
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    cli_server 'test/rackup/sleep.ru'

    skt = send_http "GET /sleep10 HTTP/1.1\r\n\r\n"
    sleep 1
    Process.kill :TERM, @pid
    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    sleep 1
    assert_raises(Errno::ECONNREFUSED) { send_http "GET /sleep0 HTTP/1.1\r\n\r\n" }

    refute_nil Process.getpgid(@pid) # ensure server is still running

    body = skt.read_body
    assert_includes body, 'Slept 10'

    Process.wait @pid
    @server.close unless @server.closed?
    @server = nil # prevent `#teardown` from killing already killed server
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT
    skip_if :jruby  # seems to intermittently lockup JRuby CI

    cli_server 'test/rackup/hello.ru'
    begin
      skt = new_socket
      skt.close
    rescue => ex
      fail("Port didn't open properly: #{ex.message}")
    end

    Process.kill :INT, @pid
    Process.kill :INT, @pid
    Process.wait @pid

    assert_raises(Errno::ECONNREFUSED) { new_socket }
  end

  def test_siginfo_thread_print
    skip_unless_signal_exist? :INFO

    cli_server 'test/rackup/hello.ru'
    Process.kill :INFO, @pid

    assert wait_for_server_to_include('Thread: TID')
  end

  def test_application_logs_are_flushed_on_write
    cli_server "#{set_pumactl_args} test/rackup/write_to_stdout.ru"

    send_http_read_response

    # below should be written before 'stop' command is issued
    assert wait_for_server_to_include("hello\n")

    cli_pumactl 'stop'

    assert wait_for_server_to_include("Goodbye")

    @server.close unless @server.closed?
    @server = nil
    @pid = nil
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM
    skip_unless :mri    # ObjectSpace.each_object(::TCPServer) ??
    skip if DARWIN && RUBY_VERSION.start_with?('2.4')
    cli_server "test/rackup/close_listeners.ru"
    skt = send_http

    if DARWIN && RUBY_VERSION < '2.6' || TRUFFLE
      begin
        skt.read_body
      rescue EOFError
      end
    else
      skt.read_body
    end

    time_limit = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5.0
    begin
      Process.kill :SIGTERM, @pid
    rescue Errno::ESRCH
    end

    # TruffleRuby may raise EOFError ?
    begin
      @server_err.wait_readable 2
      server_err = @server_err.read_nonblock 2_048
    rescue EOFError
      server_err = nil
    end

    begin
      until Process.wait2(@pid, Process::WNOHANG)
        sleep 0.2
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > time_limit
          Process.kill :SIGKILL, @pid
          flunk "Process froze"
        end
      end
    end

    # linux IOError, macOS Errno::EBADF
    assert_match(/Exception handling servers: (#<IOError: closed stream>|#<Errno::EBADF: Bad file descriptor>)/, server_err)
  end
end

class TestIntegrationSingle_2 < TestIntegration
    parallelize_me! if ::Puma::IS_MRI && !DARWIN

  def workers ; 0 ; end

  def test_write_to_log
    skip_if :windows # Errno::EACCES: Permission denied
    fn = tmp_path '.puma_log'
    cli_server "#{set_pumactl_args} test/rackup/hello.ru", config: <<~CONFIG
      log_requests
      stdout_redirect "#{fn}"
    CONFIG

    send_http_read_response

    sleep 0.01 if DARWIN

    cli_pumactl 'stop'

    # macos intermittently raises 'Errno::ENOENT: No such file'
    sleep 0.5 unless File.exist? fn
    log = File.read fn

    assert_includes log, '"GET / HTTP/1.1"'
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    fn = tmp_path '.puma_log'
    cli_server 'test/rackup/hello.ru', config: <<~CONFIG
      log_requests
      stdout_redirect "#{fn}"
      pidfile "t2-pid"
    CONFIG

    send_http_read_response

    out = cli_pumactl('-p t2-pid status', no_control_url: true).read

    sleep 0.01 if DARWIN

    stop_server

    # macos intermittently raises 'Errno::ENOENT: No such file'
    sleep 0.5 unless File.exist? fn
    log = File.read fn

    assert_includes log, '"GET / HTTP/1.1"'
    assert !File.file?("t2-pid")
    assert_equal "Puma is started\n", out
  ensure
    File.unlink 't2-pid' if File.file? 't2-pid'
  end

  def test_puma_debug_loaded_exts
    cli_server "#{set_pumactl_args} test/rackup/hello.ru", puma_debug: true, no_wait: true

    assert wait_for_server_to_include('Loaded Extensions:')
  end
end
