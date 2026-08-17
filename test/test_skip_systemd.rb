# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

require "puma/plugin"

class TestSkipSystemd < TestIntegration

  def setup
    skip_unless :linux
    skip_if :jruby

    super
  end

  def teardown
    super unless skipped?
  end

  def test_systemd_plugin_not_loaded
    cli_server "test/rackup/hello.ru",
               env: { 'PUMA_SKIP_SYSTEMD' => 'true', 'NOTIFY_SOCKET' => '/tmp/doesntmatter' }, config: <<~CONFIG
      app do |_|
        body = (Puma::Plugins.instance_variable_get(:@plugins)['systemd'] || 'nothing').to_s
        [200, {}, [body]]
      end
    CONFIG

    assert_equal 'nothing', send_http_read_body

    stop_server
  end
end
