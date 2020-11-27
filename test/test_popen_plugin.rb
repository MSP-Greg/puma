# frozen_string_literal: true

require_relative 'helpers/svr_popen'

class TestPOpenPlugin < ::TestPuma::SvrPOpen
  def test_plugin
    skip 'Skipped on Windows Ruby < 2.5.0, Ruby bug' if windows? && RUBY_VERSION < '2.5.0'
    setup_puma config: "plugin 'tmp_restart'"
    ctrl_type :tcp

    Dir.mkdir 'tmp' unless Dir.exist? 'tmp'

    start_puma 'test/rackup/hello.ru'
    File.write 'tmp/restart.txt', "Restart #{Time.now}\n", mode: 'wb:UTF-8'

    assert_server_gets cmd_to_log_str(:restart)
  end
end
