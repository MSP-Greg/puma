# frozen_string_literal: true

require_relative 'helpers/svr_popen'
require_relative 'test_popen_common.rb'
require 'sd_notify'

class TestPOpenSystemd < ::TestPuma::SvrPOpen
    parallelize_me! if ::Puma.mri?
    include TestPOpenCommon

  def setup
    skip 'Skipped because Systemd support is linux-only' unless RUBY_PLATFORM.include?('linux')
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_if :jruby

    super

    Dir::Tmpname.create('puma_socket') do |sockaddr|
      @sockaddr = sockaddr
      @socket = Socket.new :UNIX, :DGRAM, 0
      socket_ai = Addrinfo.unix sockaddr
      @socket.bind socket_ai
      ENV['NOTIFY_SOCKET'] = sockaddr
    end
  end

  def teardown
    return if skipped?
    @socket.close if @socket
    File.unlink @sockaddr if @sockaddr
    @socket = nil
    @sockaddr = nil
    ENV['NOTIFY_SOCKET'] = nil
    ENV['WATCHDOG_USEC'] = nil
  end

  def socket_message
    @socket.recvfrom(15)[0]
  end

  def test_systemd_notify_usr1_phased_restart_cluster
    restart :USR1
  end

  def test_systemd_notify_usr2_hot_restart_cluster
    restart :USR2
  end

  def test_systemd_notify_usr2_hot_restart_single
      restart :USR2, workers: 0
  end

  def test_systemd_watchdog
    ENV['WATCHDOG_USEC'] = '1_000_000'

    start_puma 'test/rackup/hello.ru'

    assert_equal socket_message, 'READY=1'
    assert_equal socket_message, 'WATCHDOG=1'

    Process.kill :TERM, @pid
    assert_match socket_message, 'STOPPING=1'
  end

  def test_systemd_socket_activate_usr2_hot_restart
    skip_unless :mri
    ctrl = UniquePort.call

    setup_puma :tcp, config: -> () {
      <<RUBY
threads 5, 5
set_default_host '#{HOST}'
port #{@bind_port}
workers 2
activate_control_app 'tcp://#{HOST}:#{ctrl}', no_token: true
rackup 'test/rackup/hello.ru'
RUBY
    }

    ctrl_type config_path: @config_path

    cmd = "systemd-socket-activate -l#{HOST}:#{@bind_port} bundle exec --keep-file-descriptors ruby -Ilib bin/puma -C #{@config_path}"

    @server = IO.popen cmd, 'r', :err=>[:child, :out]

    # use curl since it will retry
    assert(system "curl #{HOST}:#{@bind_port} -o /dev/null", :err => '/dev/null')

    cli_pumactl :restart

    assert_server_gets cmd_to_log_str(:restart)

    assert_includes connect_get_body(len: 10), 'Hello World'
  ensure
    Process.kill('KILL', @server.pid) if @server.is_a? ::IO
    @server = nil
  end

  private

  def restart(signal, workers: 2)
    start_puma '-w#{workers} test/rackup/hello.ru'
    assert_equal socket_message, 'READY=1'

    Process.kill signal, @pid
    assert_equal socket_message, 'RELOADING=1'
    assert_equal socket_message, 'READY=1'

    Process.kill :TERM, @pid
    assert_equal socket_message, 'STOPPING=1'
  end
end
