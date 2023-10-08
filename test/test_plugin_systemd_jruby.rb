# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/test_puma/server_spawn"

class TestPluginSystemdJruby < TestPuma::ServerSpawn

  def setup
    skip_unless :linux
    skip_unless :unix
    skip_unless_signal_exist? :TERM
    skip_unless :jruby
  end

  def test_systemd_plugin_not_loaded
    server_spawn "test/rackup/hello.ru",
      env: {'NOTIFY_SOCKET' => '/tmp/doesntmatter' }, config: <<~CONFIG
      app do |_|
        [200, {}, [Puma::Plugins.instance_variable_get(:@plugins)['systemd'].to_s]]
      end
    CONFIG

    assert_empty send_http_read_body
  end
end
