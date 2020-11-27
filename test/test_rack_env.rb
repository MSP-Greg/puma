require_relative 'helpers/svr_in_proc'

class TestRackEnv < ::TestPuma::SvrInProc
  parallelize_me!

  def test_normalize_host_header_missing_tcp
    assert_host_header "", "localhost", 80
  end

  def test_normalize_host_header_missing_ssl
    skip_unless :ssl
    setup_server :ssl
    assert_host_header "", "localhost", 443
  end

  def test_normalize_host_header_hostname
    assert_host_header "Host: example.com:456", "example.com", 456

    assert_host_header "Host: example.com", "example.com", 80
  end

  def test_normalize_host_header_ipv4
    assert_host_header "Host: 123.123.123.123:456", "123.123.123.123", 456

    assert_host_header "Host: 123.123.123.123", "123.123.123.123", 80
  end

  def test_normalize_host_header_ipv6
    assert_host_header "Host: [::1]:9292", "[::1]", 9292

    assert_host_header "Host: [::1]", "[::1]", 80
  end

  def test_default_server_port_respects_x_forwarded_proto
    assert_host_header "Host: example.com\r\nX-Forwarded-Proto: https,http",
      "example.com", 443
  end

  def test_proper_stringio_body
    data = nil

    start_server do |env|
      data = env['rack.input'].read
      [200, {}, ["ok"]]
    end

    fifteen = "1" * 15

    sock = connect_raw "PUT / HTTP/1.0\r\nContent-Length: 30\r\n\r\n#{fifteen}"

    sleep 0.1 # important so that the previous data is sent as a packet
    sock << fifteen

    sock.read

    assert_equal "#{fifteen}#{fifteen}", data
  end

  def test_puma_socket
    body = "HTTP/1.1 750 Upgraded to Awesome\r\nDone: Yep!\r\n"
    start_server do |env|
      io = env['puma.socket']
      io.write body
      io.close
      [-1, {}, []]
    end

    assert_equal body, connect_raw("PUT / HTTP/1.0\r\n\r\nHello").read
  end

  def test_rack_url_scheme_http
    # default bind is tcp
    rack_url_scheme 'http'
  end

  # Check if UNIXSocket binds are reported as http
  def test_rack_url_scheme_aunix_http
    skip_unless :aunix
    setup_server :aunix
    rack_url_scheme 'http'
  end

  def test_rack_url_scheme_https
    skip_unless :ssl
    setup_server :ssl
    rack_url_scheme 'https'
  end

  def test_rack_url_scheme_user
    setup_server config: "rack_url_scheme 'user'"
    rack_url_scheme 'user'
  end

  private

  def start_host_header_sock
    start_server do |env|
      [200, {}, [env["SERVER_NAME"], "\n", env["SERVER_PORT"]]]
    end
    @sock = connect
  end

  def assert_host_header(hdr, host, port)
    start_host_header_sock unless @server
    if hdr.empty?
      @sock << "GET / HTTP/1.1\r\n\r\n"
    else
      @sock << "GET / HTTP/1.1\r\n#{hdr}\r\n\r\n"
    end
    assert "#{host}\n#{port}", @sock.read_body
  end

  def rack_url_scheme(val)
    start_server { |env| [200, {}, [env["rack.url_scheme"]]] }
    assert_includes connect_get_body, val
  end
end
