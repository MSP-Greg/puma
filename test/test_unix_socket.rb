# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/tmp_path"
require_relative "helpers/test_puma/puma_socket"

class TestPumaUnixSocket < Minitest::Test
  include TmpPath
  include TestPuma::PumaSocket

  EXPECTED_RESPONSE = "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nWorks"

  APP = lambda { |env| [200, {}, ["Works"]] }

  def teardown
    @server.stop(true) unless skipped? || @server.nil?
  end

  def server_unix(type)
    skip_unless type
    @bind_path = type == :unix ? tmp_path('.sock') : "@TestPumaUnixSocket"
    @server = Puma::Server.new APP
    @server.add_unix_listener @bind_path
    @server.run

    assert_equal EXPECTED_RESPONSE, send_http_read_response
  end

  def test_server_unix
    server_unix :unix
  end

  def test_server_aunix
    server_unix :aunix
  end
end
