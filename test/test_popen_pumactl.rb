# frozen_string_literal: true

require_relative 'helpers/svr_popen'

class TestPOpenPumactl < ::TestPuma::SvrPOpen
  parallelize_me! if ::Puma.mri?

  def test_stop_state_tcp
    skip_if :jruby, :truffleruby # Undiagnose thread race. TODO fix
    ctrl_type :state_tcp
    shutdown 'stop'
  end

  def test_stop_tcp
    skip_if :jruby, :truffleruby # Undiagnose thread race. TODO fix
    ctrl_type :tcp
    shutdown 'stop'
  end

  def test_stop_unix
    skip_unless :unix
    ctrl_type :unix
    shutdown 'stop'
  end

  def test_stop_abstract_unix
    skip_unless :aunix
    ctrl_type :aunix
    shutdown 'stop'
  end

  def test_halt_state_unix
    skip_if :jruby, :truffleruby # Undiagnose thread race. TODO fix
    skip_unless :unix
    ctrl_type :state_unix
    shutdown 'halt'
  end

  def test_halt_tcp
    skip_if :jruby, :truffleruby # Undiagnose thread race. TODO fix
    ctrl_type :tcp
    shutdown 'halt'
  end

  def test_halt_unix
    skip_unless :unix
    ctrl_type :unix
    shutdown 'halt'
  end

  def test_prune_bundler_with_multiple_workers
    skip_unless :fork
    skip_unless :unix

    setup_puma :unix, config_path: 'test/config/prune_bundler_with_multiple_workers.rb'
    ctrl_type :unix

    start_puma '-q'

    hdrs, body = connect_get_response 'sleep1'

    assert_match '200 OK', hdrs
    assert_match 'embedded app', body
  end

  def test_kill_unknown
    skip_if :jruby

    # we run ls to get a 'safe' pid to pass off as puma in cli stop
    # do not want to accidentally kill a valid other process
    io = IO.popen(windows? ? "dir" : "ls")
    safe_pid = io.pid
    Process.wait safe_pid

    sout = StringIO.new

    e = assert_raises SystemExit do
      Puma::ControlCLI.new(%W!-p #{safe_pid} stop!, sout).run
    end
    sout.rewind
    # windows bad URI(is not URI?)
    io.close unless io.closed?
    assert_match(/No pid '\d+' found|bad URI\(is not URI\?\)/, sout.readlines.join(""))
    assert_equal(1, e.status)
  end

  private

  def shutdown(command)
    stderr = tmp_path '.stderr'
    setup_puma config: "stdout_redirect nil, '#{stderr}'"

    start_puma '-q test/rackup/ci_string.ru'

    cli_pumactl command
    assert_server_gets cmd_to_log_str(command)

    if Puma.windows?
      sleep 0.2
      begin
        _, status = Process.wait2 @pid
      rescue Errno::ECHILD
        status = 0
      end
    else
      _, status = Process.wait2 @pid
    end

    err = File.read(stderr)
    refute_match 'ERROR', err
    assert_equal 0, status

    self.stopped = true

    @server.close
    @server = nil
  end
end
