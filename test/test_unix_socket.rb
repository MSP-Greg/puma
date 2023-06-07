# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/puma_socket"

class TestPumaUnixSocket < Minitest::Test
  include TestPuma::PumaSocket

  def teardown
    return if skipped?
    @server.stop(true)
  end

  def server_unix(type)
    app = lambda { |env| [200, {}, [env['puma.socket'].path]] }
    @bind_path = type == :unix ? tmp_unix('.sock') : "@#{full_name}"
    @server = Puma::Server.new app, nil, {min_threads: 1}
    @server.add_unix_listener @bind_path
    bind_path = @bind_path.sub "@", "\u0000"
    if Puma::IS_JRUBY
      # JRuby may not return the path, either by #path or #peeraddr
      @expected = "HTTP/1.0 200 OK\r\nContent-Length: 0\r\n\r\n"
    else
      @expected = "HTTP/1.0 200 OK\r\nContent-Length: #{bind_path.bytesize}\r\n\r\n#{bind_path}"
    end
    @server.run
  end

  def test_server_unix
    skip_unless :unix
    server_unix :unix

    resp = send_http_read_response "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    assert_equal @expected, resp
  end

  def test_server_aunix
    skip_unless :aunix
    server_unix :aunix

    resp = send_http_read_response "GET / HTTP/1.0\r\nHost: blah.com\r\n\r\n"

    assert_equal @expected, resp
  end
end
