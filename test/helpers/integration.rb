# frozen_string_literal: true

require "puma/control_cli"
require "json"
require "io/wait" unless Puma::HAS_NATIVE_IO_WAIT

require_relative 'puma_socket'

class TestIntegration < Minitest::Test
  DARWIN = RUBY_PLATFORM.include? 'darwin'
  HOST  = "127.0.0.1"
  TOKEN = "xxyyzz"
  RESP_READ_LEN = 65_536
  RESP_READ_TIMEOUT = 10
  RESP_SPLIT = "\r\n\r\n"

  WAIT_SERVER_TIMEOUT =
    if    ::Puma::IS_MRI  ; 10
    elsif ::Puma::IS_JRUBY; 15
    else                  ; 15 # TruffleRuby
    end

  BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
    "#{Gem.ruby} -Ilib"

  PID_QUEUE = Queue.new

  prepend ::TestPuma::PumaSocket

  def before_setup
    super
    @server = nil
    @server_err = nil
    @check_server_err = true
    @pid = nil
    @bind_path = nil
    @stop_server_called = false
  end

  def after_teardown
    return if skipped?
    super
    err_out = ''

    if @server_err.is_a?(IO) && @check_server_err
      begin
        if @server_err.wait_readable 0.25
          err_out = @server_err.read_nonblock(2_048, exception: false) || ''
        end
        @server_err.close
      rescue IOError, Errno::EBADF
      end
    end

    unless @stop_server_called
      if @server && defined?(@control_tcp_port)
        cli_pumactl 'stop'
        begin
          if @server.wait_readable 1
            assert wait_for_server_to_include 'Goodbye!'
          end
        rescue RuntimeError, IOError
        end
      elsif @server && @pid && !Puma::IS_WINDOWS
        stop_server @pid, signal: :INT
      end
      @server.close if @server.respond_to?(:close) && !@server.closed?
      @server = nil

      if @pid
        begin
          Process.wait2 @pid
        rescue Errno::ECHILD
        end
      end
    end

    if @bind_path
      refute File.exist?(@bind_path), "Bind path must be removed after stop"
      File.unlink(@bind_path) rescue nil
    end

    unless err_out.strip.empty?
      begin
        STDOUT.syswrite "\n----------------------------------- " \
          "err_out\n#{err_out.strip}\n"
      rescue ThreadError
      end
    end
  end

  private

  def silent_and_checked_system_command(*args)
    assert system(*args, out: File::NULL, err: File::NULL)
  end

  def cli_server(argv,    # rubocop:disable Metrics/ParameterLists
      unix: false,        # uses a UNIXSocket for the server listener when true
      config: nil,        # string to use for config file
      log: false,         # output server log to console (for debugging)
      no_wait: false,     # don't wait for server to boot
      puma_debug: nil,    # set env['PUMA_DEBUG'] = 'true'
      config_bind: false, # use bind from config
      env: {})            # pass env setting to Puma process in spawn_cmd
    if config
      path = tmp_file_path %w[config .rb], config
      config = "-C #{path}"
    end

    puma_path = File.expand_path '../../../bin/puma', __FILE__
    cmd = +"#{BASE} #{puma_path} #{config}"

    unless config_bind
      if unix
        @bind_path ||= tmp_unix '.bind'
        cmd << " -b unix://#{@bind_path}"
      else
        @tcp_port = UniquePort.call
        cmd << " -b tcp://#{HOST}:#{@tcp_port}"
      end
    end
    argv = argv.join(' ') if argv.is_a? Array
    cmd << " #{argv}" if argv

    env['PUMA_DEBUG'] = 'true' if puma_debug

    @server, @server_err, @pid = spawn_cmd env, cmd
    # =below helpful may be helpful for debugging
    # STDOUT.syswrite "\nPID #{@pid} #{self.class.to_s}##{name}\n"

    PID_QUEUE << [@pid, full_name]

    wait_for_server_to_boot(log: log) unless no_wait
    @server
  end

  # rescue statements are just in case method is called with a server
  # that is already stopped/killed, especially since Process.wait2 is
  # blocking
  def stop_server(pid = @pid, signal: :TERM)
    @check_server_err = false
    begin
      Process.kill signal, pid
    rescue Errno::ESRCH
    end
    @server.close if @server.respond_to?(:close) && !@server.closed?
    @server = nil
    @stop_server_called = true
    ret = nil
    Thread.new {
      ret = begin
        Process.wait2 pid
      rescue Errno::ECHILD, Errno::ESRCH
      end
    }.join(10)
    ret
  end

  def restart_server_and_listen(argv, log: false)
    cli_server argv, log: log
    socket = send_http
    initial_reply = socket.read_body
    restart_server socket
    [initial_reply, send_http_read_resp_body]
  end

  # reuses an existing connection to make sure that works
  def restart_server(socket, log: false)
    Process.kill :USR2, @pid
    socket.syswrite "GET / HTTP/1.1\r\n\r\n" # trigger it to start by sending a new request
    wait_for_server_to_boot log: log
  end

  # wait for server to say it booted
  # @server and/or @server.gets may be nil on slow CI systems
  def wait_for_server_to_boot(no_error: false, log: false)
    host_re = Regexp.escape HOST
    t1 = wait_for_server_to_include 'Ctrl-C', log: log
    if (bind = @log_out[/Listening on (http|ssl):\/\/(#{host_re}|\[::1\]):(\d{4,5})($|\?)/, 3])
      @tcp_port ||= bind
    end
    t1
  rescue => e
    unless no_error
      if @server_err.wait_readable 1
        if (err = @server_err&.read&.strip || '') && !err.empty?
          STDOUT.syswrite "\n------------------ Server Error log:\n#{err}\n"
        end
      end
      raise e.message
    end
  end

  # Returns true if and when server log includes str.
  # Will timeout or raise an error otherwise
  def wait_for_server_to_include(str, io: @server, log: false, ret_false_str: nil)
    wait_readable_timeouts = 0
    @log_out = +''
    @log_out << "Waiting for '#{str}'  #{full_name}\n"

    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SERVER_TIMEOUT
    sleep 0.05 until io.is_a?(IO) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > t_end
    raise "Waited too long for server to init (must be an io)" unless io.is_a? IO

    begin
      loop do
        if io.wait_readable 2
          line = io&.gets
          @log_out << line if line
          if line&.include? str
            STDOUT.syswrite "\n#{@log_out}\n" if log
            return true
          end
        elsif t_end < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          unless wait_readable_timeouts.zero?
            @log_out << "#{wait_readable_timeouts} io.wait_readable timeouts, 2 sec each\n"
          end
          STDOUT.syswrite "\n#{@log_out}\n"
          raise "Waited too long for server log to include '#{str}'"
        else
          sleep 0.01 # io.wait_readable may immediately return !true
          wait_readable_timeouts += 1
        end
      end
    rescue Errno::EBADF, Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
      STDOUT.syswrite "\n#{@log_out}\n"
      raise "#{e.class} #{e.message}\n  while waiting for server log to include '#{str}'"
    end
  end

  # Returns line if and when server log matches re, unless idx is specified,
  # then returns regex match.
  # Will timeout or raise an error otherwise
  def wait_for_server_to_match(re, idx = nil, io: @server, log: false, ret_false_re: nil)
    wait_readable_timeouts = 0
    log_out = +''
    log_out << "Waiting for '#{re.inspect}'  #{full_name}\n"

    t_end = Process.clock_gettime(Process::CLOCK_MONOTONIC) + WAIT_SERVER_TIMEOUT
    sleep 0.05 until io.is_a?(IO) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > t_end
    raise "Waited too long for server to init (must be an io)" unless io.is_a? IO

    begin
      loop do
        if io.wait_readable 2
          line = io&.gets
          log_out << line if line
          if ret_false_re&.match? line
            STDOUT.syswrite "\n#{log_out}\n" if log
            return false
          end
          if line&.match?(re)
            STDOUT.syswrite "\n#{log_out}\n" if log
            return (idx ? line[re, idx] : line)
          end
        elsif t_end < Process.clock_gettime(Process::CLOCK_MONOTONIC)
          unless wait_readable_timeouts.zero?
            log_out << "    #{wait_readable_timeouts} io.wait_readable timeouts, 2 sec each\n" \
              "    #{full_name}\n"
          end
          STDOUT.syswrite "\n#{log_out}\n"
          raise "Waited too long for server log to match '#{re.inspect}'"
        else
          sleep 0.01 # io.wait_readable may immediately return !true
          wait_readable_timeouts += 1
        end
      end
    rescue Errno::EBADF, Errno::ECONNREFUSED, Errno::ECONNRESET, IOError => e
      STDOUT.syswrite "\n#{log_out}\n"
      raise "#{e.class} #{e.message}\n  while waiting for server log to match '#{re.inspect}'"
    end
  end

  # gets worker pids from @server output
  def get_worker_pids(phase = 0, size = workers, log: nil)
    pids = []
    re = /\(PID: (\d+)\) booted in [.0-9]+s, phase: #{phase}/
    while pids.size < size
      if pid = wait_for_server_to_match(re, 1, log: log)
        pids << pid
      end
    end
    pids.map(&:to_i)
  end

  # used to define correct 'refused' errors
  def thread_run_refused(unix: false)
    if unix
      DARWIN ? [IOError, Errno::ENOENT, Errno::EPIPE, Errno::ENOTSOCK] :
               [IOError, Errno::ENOENT, Errno::ENOTSOCK]
    else
      # Errno::ECONNABORTED is thrown intermittently on TCPSocket.new
      DARWIN ? [IOError, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EBADF, EOFError, Errno::ECONNABORTED, Errno::ENOTSOCK] :
               [IOError, Errno::ECONNREFUSED, Errno::EPIPE, Errno::EBADF, Errno::ENOTSOCK]
    end
  end

  def set_pumactl_args(unix: false)
    if unix
      @control_path = tmp_unix '.cntl_sock'
      "--control-url=unix://#{@control_path} --control-token=#{TOKEN}"
    else
      @control_tcp_port = UniquePort.call
      "--control-url=tcp://#{HOST}:#{@control_tcp_port} --control-token=#{TOKEN}"
    end
  end

  def cli_pumactl(argv, unix: false, no_control_url: false)
    base =
      if no_control_url
        []
      elsif unix
        %W[-C unix://#{@control_path} -T #{TOKEN}]
      else
        %W[-C tcp://#{HOST}:#{@control_tcp_port} -T #{TOKEN}]
      end
    arg = base + argv.split
    r, w = IO.pipe
    # Puma::ControlCLI may call exit
    begin
      Puma::ControlCLI.new(arg, w, w).run
    rescue Exception
    end
    w.close
    @ios_to_close << r
    @stop_server_called = true if argv == 'stop'
    r
  end

  def get_stats
    read_pipe = cli_pumactl "stats"
    JSON.parse(read_pipe.readlines.last)
  end

  def hot_restart_does_not_drop_connections(num_threads: 1, total_requests: 500)
    puma_skipped = true
    skip_if :jruby, suffix: "- JRuby file descriptors are not preserved on exec, " \
      "connection reset errors are expected during restarts"

    skip_if :truffleruby, suffix: ' - Undiagnosed failures on TruffleRuby'
    puma_skipped = false

    args = "-w#{workers} -t5:5 -q test/rackup/hello_with_delay.ru"
    if Puma.windows?
      cli_server "#{set_pumactl_args} #{args}"
    else
      cli_server args
    end

    replies = Hash.new 0
    refused = thread_run_refused unix: false
    message = 'A' * 16_256  # 2^14 - 128

    mutex = Mutex.new
    restart_count = 0
    client_threads = []

    num_requests = (total_requests/num_threads).to_i

    req_loop = -> () {
      req_str = "POST / HTTP/1.1\r\nContent-Length: #{message.bytesize}\r\n\r\n#{message}"
      num_requests.times do |req_num|
        begin
          begin
            socket = send_http req_str
          rescue => e
            replies[:write_error] += 1
            raise e
          end
          body = socket.read_body
          if body == "Hello World"
            mutex.synchronize {
              replies[:success] += 1
              replies[:restart] += 1 if restart_count > 0
            }
          else
            mutex.synchronize { replies[:unexpected_response] += 1 }
          end
        rescue Errno::ECONNRESET, Errno::EBADF, Errno::ENOTCONN
          # connection was accepted but then closed
          # client would see an empty response
          # Errno::EBADF Windows may not be able to make a connection
          mutex.synchronize { replies[:reset] += 1 }
        rescue *refused
          # IOError intermittently thrown by Ubuntu, add to allow retry
          mutex.synchronize { replies[:refused] += 1 }
        rescue ::Timeout::Error
          mutex.synchronize { replies[:read_timeout] += 1 }
        ensure
          if socket.is_a?(IO) && !socket.closed?
            begin
              socket.close
            rescue Errno::EBADF
            end
          end
        end
      end
    }

    run = true

    restart_thread = Thread.new do
      sleep 0.2  # let some connections in before 1st restart
      while run
        if Puma.windows?
          cli_pumactl 'restart'
        else
          Process.kill :USR2, @pid
        end
        wait_for_server_to_boot(no_error: true)
        restart_count += 1
        sleep(Puma.windows? ? 2.0 : 0.5)
      end
    end

    if num_threads > 1
      num_threads.times do |thread|
        client_threads << Thread.new do
          req_loop.call
        end
      end
    else
      req_loop.call
    end

    client_threads.each(&:join) if num_threads > 1
    run = false
    restart_thread.join
    if Puma.windows?
      cli_pumactl 'stop'
      Process.wait @pid
    else
      stop_server
    end
    @server = nil

    msg = ("   %4d unexpected_response\n"   % replies.fetch(:unexpected_response,0)).dup
    msg << "   %4d refused\n"               % replies.fetch(:refused,0)
    msg << "   %4d read timeout\n"          % replies.fetch(:read_timeout,0)
    msg << "   %4d reset\n"                 % replies.fetch(:reset,0)
    msg << "   %4d success\n"               % replies.fetch(:success,0)
    msg << "   %4d success after restart\n" % replies.fetch(:restart,0)
    msg << "   %4d restart count\n"         % restart_count

    refused = replies[:refused]
    reset   = replies[:reset]

    if Puma.windows?
      reset_max = num_threads * restart_count
      assert_operator reset_max, :>=, reset  , "#{msg}Expected reset_max >= reset errors"
      assert_operator reset_max, :>=, refused, "#{msg}Too many refused connections"
    else
      max_error = (0.002 * replies.fetch(:success,0) + 0.5).round
      assert_operator max_error, :>=, refused, "#{msg}Expected no more than #{max_error} refused connections"
      assert_operator max_error, :>=, reset  , "#{msg}Expected no more than #{max_error} reset connections"
    end
    assert_equal 0, replies[:unexpected_response], "#{msg}Unexpected response"
    assert_equal 0, replies[:read_timeout], "#{msg}Expected no read timeouts"

    assert_equal (num_threads * num_requests) - reset - refused, replies[:success]

  ensure
    unless puma_skipped
      if passed?
        refused = replies[:refused]
        reset   = replies[:reset]
        msg = "    #{restart_count} restarts, #{reset} resets, #{refused} refused, " \
          "#{replies[:restart]} success after restart, #{replies[:write_error]} write error"
        $debugging_info << "#{full_name}\n#{msg}\n"
      else
        client_threads.each { |thr| thr.kill if thr.is_a? Thread }
        $debugging_info << "#{full_name}\n#{msg}\n"
      end
    end
  end

  def spawn_cmd(env = {}, cmd)
    opts = {}

    out_r, out_w = IO.pipe
    opts[:out] = out_w

    err_r, err_w = IO.pipe
    opts[:err] = err_w

    pid = spawn(env, cmd, opts)
    [out_w, err_w].each(&:close)
    [out_r, err_r, pid]
  end
end
