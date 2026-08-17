# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestIntegrationSingle < TestIntegration
  parallelize_me!

  def workers ; 0 ; end

  def test_hot_restart_does_not_drop_connections_threads
    ttl_reqs = Puma.windows? ? 500 : 1_000
    restart_does_not_drop_connections num_threads: 5, total_requests: ttl_reqs,
      signal: :USR2
  end

  def test_hot_restart_does_not_drop_connections
    if Puma.windows?
      restart_does_not_drop_connections total_requests: 300,
        signal: :USR2
    else
      restart_does_not_drop_connections signal: :USR2
    end
  end

  def test_usr2_restart
    skip_unless_signal_exist? :USR2
    response_1, response_2 = restart_server_and_listen("-q test/rackup/hello.ru")
    assert_equal "Hello World", response_1
    assert_equal "Hello World", response_2
  end

  # It does not share environments between multiple generations, which would break Dotenv
  def test_usr2_restart_restores_environment
    # jruby has a bug where setting `nil` into the ENV or `delete` do not change the
    # next workers ENV
    skip_if :jruby
    skip_unless_signal_exist? :USR2

    response_1, response_2 = restart_server_and_listen("-q test/rackup/hello-env.ru")

    assert_includes response_1, "Hello RAND"
    assert_includes response_2, "Hello RAND"
    refute_equal response_1, response_2
  end

  def test_term_exit_code
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/hello.ru"
    _, status = stop_server

    status = status.exitstatus % 128 if ::Puma::IS_JRUBY
    assert_equal 15, status
  end

  def test_after_booted_and_after_stopped
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/event_after_booted_and_after_stopped.rb -C test/config/event_after_booted_exit.rb test/rackup/hello.ru",
      no_wait: true

    assert wait_for_server_to_include('after_booted called')
    assert wait_for_server_to_include('after_stopped called')

    wait_server 15
  end

  def test_term_suppress
    skip_unless_signal_exist? :TERM

    cli_server "-C test/config/suppress_exception.rb test/rackup/hello.ru"
    _, status = stop_server

    assert_equal 0, status
  end

  def test_rack_url_scheme_default
    cli_server "#{set_pumactl_args} test/rackup/url_scheme.ru"

    assert_match "http", send_http_read_body
  end

  def test_conf_is_loaded_before_passing_it_to_binder
    cli_server "test/rackup/url_scheme.ru", config: <<~CONFIG
      #{set_pumactl_config}
      rack_url_scheme 'https'
    CONFIG

    assert_match "http", send_http_read_body
  end

  def test_prefer_rackup_file_specified_by_cli
    cli_server "test/rackup/hello.ru", config: <<~CONFIG
      #{set_pumactl_config}
      rackup 'test/rackup/hello-env.ru'
    CONFIG

    assert_equal "Hello World", send_http_read_body
  end

  def test_term_not_accepts_new_connections
    skip_unless_signal_exist? :TERM

    cli_server 'test/rackup/sleep.ru'

    _stdin, curl_stdout, _stderr, curl_wait_thread = Open3.popen3({ 'LC_ALL' => 'C' }, "curl http://#{HOST}:#{@bind_port}/sleep10")
    sleep 1 # ensure curl send a request

    Process.kill :TERM, @pid
    assert wait_for_server_to_include('Gracefully stopping') # wait for server to begin graceful shutdown

    # Invoke a request which must be rejected
    _stdin, _stdout, rejected_curl_stderr, rejected_curl_wait_thread = Open3.popen3("curl #{HOST}:#{@bind_port}")

    refute_nil Process.getpgid(@server.pid) # ensure server is still running
    refute_nil Process.getpgid(curl_wait_thread[:pid]) # ensure first curl invocation still in progress

    curl_wait_thread.join
    rejected_curl_wait_thread.join

    re_curl_error = TRUFFLE ?
      /Connection (refused|reset by peer)|(Couldn't|Could not) connect to server/ :
      /Connection refused|(Couldn't|Could not) connect to server/

    assert_match(/Slept 10/, curl_stdout.read)
    assert_match(re_curl_error, rejected_curl_stderr.read)

    wait_server 15
  end

  def test_int_refuse
    skip_unless_signal_exist? :INT

    cli_server 'test/rackup/hello.ru'
    begin
      new_socket.close
    rescue => ex
      fail "Port didn't open properly: #{ex.message}"
    end

    Process.kill :INT, @pid
    wait_server

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

    suppress_output = '> /dev/null 2>&1'

    cli_server '-C test/config/t1_conf.rb test/rackup/hello.ru'

    system "curl http://localhost:#{@bind_port}/ #{suppress_output}"

    stop_server

    log = File.read('t1-stdout')

    assert_match(%r!GET / HTTP/1\.1!, log)
  ensure
    File.unlink 't1-stdout' if File.file? 't1-stdout'
    File.unlink 't1-pid'    if File.file? 't1-pid'
  end

  def test_puma_started_log_writing
    skip_unless_signal_exist? :TERM

    cli_server '-C test/config/t2_conf.rb test/rackup/hello.ru'

    system "curl http://localhost:#{@bind_port}/ > /dev/null 2>&1"

    out=`#{BASE} bin/pumactl -F test/config/t2_conf.rb status`

    stop_server

    log = File.read('t2-stdout')

    assert_match(%r!GET / HTTP/1\.1!, log)
    assert(!File.file?("t2-pid"))
    assert_equal("Puma is started\n", out)
  ensure
    File.unlink 't2-stdout' if File.file? 't2-stdout'
  end

  def test_puma_started_log_writing_with_custom_logging
    skip_unless_signal_exist? :TERM

    cli_server '-C test/config/t4_conf.rb test/rackup/hello.ru'

    system "curl http://localhost:#{@bind_port}/ > /dev/null 2>&1"

    out=`#{BASE} bin/pumactl -F test/config/t4_conf.rb status`

    stop_server

    log = File.read('t4-stdout')

    assert_match(%r!Custom logging: 127\.0\.0\.1.*GET / HTTP/1\.1!, log)
    assert(!File.file?("t4-pid"))
    assert_equal("Puma is started\n", out)
  ensure
    File.unlink 't4-stdout' if File.file? 't4-stdout'
  end

  def test_application_logs_are_flushed_on_write
    cli_server "#{set_pumactl_args} test/rackup/write_to_stdout.ru"

    send_http_read_body

    cli_pumactl 'stop'

    assert wait_for_server_to_include("hello\n")
    assert wait_for_server_to_include("Goodbye!")

    wait_server
  end

  # listener is closed 'externally' while Puma is in the IO.select statement
  def test_closed_listener
    skip_unless_signal_exist? :TERM

    cli_server "test/rackup/close_listeners.ru", merge_err: true

    socket = send_http

    begin
      socket.read_body
    rescue EOFError
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
    assert wait_for_server_to_include('Goodbye!')
    wait_server
  end

  def test_idle_timeout
    cli_server "test/rackup/hello.ru", config: "idle_timeout 1\n" \
      "#{set_pumactl_config}"

    send_http

    sleep 1.15

    assert_raises Errno::ECONNREFUSED, "Connection refused" do
      send_http
    end

    wait_server
  end

  def test_pre_existing_unix_after_idle_timeout
    skip_unless :unix

    File.binwrite bind_path, 'pre existing'

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
