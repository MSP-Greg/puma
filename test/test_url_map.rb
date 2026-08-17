# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/integration"

class TestURLMap < TestIntegration

  def teardown
    return if skipped?
    super
  end

  # make sure the mapping defined in url_map_test/config.ru works
  def test_basic_url_mapping
    skip_if :jruby
    env = { "BUNDLE_GEMFILE" => "#{__dir__}/url_map_test/Gemfile" }
    Dir.chdir("#{__dir__}/url_map_test") do
      cli_server set_pumactl_args, env: env
    end

    body = send_http("GET /ok HTTP/1.1\r\nhost: test.com\r\n\r\n").read_body
    assert_equal("OK", body)
  end
end
