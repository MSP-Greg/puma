# frozen_string_literal: true

require_relative "helper"
require_relative "helpers/puma_socket"

# don't load Rack, as it autoloads everything
begin
  require "rack/body_proxy"
  require "rack/lint"
  require "rack/version"
  require "rack/common_logger"
rescue LoadError # Rack 1.6
  require "rack"
end

# Rack::Chunked is loaded by Rack v2, needs to be required by Rack 3.0,
# and is removed in Rack 3.1
require "rack/chunked" if Rack.release.start_with? '3.0'

require "nio"

class TestRackServer < Minitest::Test
  parallelize_me!

  include TestPuma::PumaSocket

  HOST = '127.0.0.1'

  STR_1KB = "──#{SecureRandom.hex 507}─\n".freeze

  class ErrorChecker
    def initialize(app)
      @app = app
      @exception = nil
    end

    attr_reader :exception, :env

    def call(env)
      begin
        @app.call(env)
      rescue Exception => e
        @exception = e
        [ 500, {}, ["Error detected"] ]
      end
    end
  end

  class ServerLint < Rack::Lint
    def call(env)
      if Rack.release < '3'
        check_env env
      else
        Wrapper.new(@app, env).check_environment env
      end

      @app.call(env)
    end
  end

  def setup
    @simple = lambda { |env| [200, { "x-header" => "Works" }, ["Hello"]] }
    @server = Puma::Server.new @simple
    @port = (@server.add_tcp_listener HOST, 0).addr[1]
    @tcp = "http://#{HOST}:#{@port}"
    @stopped = false
  end

  def stop
    @server.stop(true)
    @stopped = true
  end

  def teardown
    @server.stop(true) unless @stopped
  end

  def header_hash(str)
    t = str.split "\r\n"
    t.shift; t.map! { |line| line.split(/:\s?/) }
    t.to_h
  end

  def test_lint
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    send_http_read_response GET_11

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_large_post_body
    @checker = ErrorChecker.new ServerLint.new(@simple)
    @server.app = @checker

    @server.run

    big = "x" * (1024 * 16)

    body = "big=#{big}"

    hdrs = "Content-Type: application/x-www-form-urlencoded\r\n" \
           "Content-Length: #{body.bytesize}\r\n"

    send_http "POST /test HTTP/1.1\r\n#{hdrs}\r\n#{body}"

    stop

    refute @checker.exception, "Checker raised exception"
  end

  def test_path_info
    input = nil
    @server.app = lambda { |env| input = env; @simple.call(env) }
    @server.run

    send_http_read_response "GET /test/a/b/c HTTP/1.1\r\n\r\n"

    stop

    assert_equal "/test/a/b/c", input['PATH_INFO']
  end

  def test_after_reply
    closed = false

    @server.app = lambda do |env|
      env['rack.after_reply'] << lambda { closed = true }
      @simple.call(env)
    end

    @server.run

    send_http_read_response "GET /test HTTP/1.1\r\n\r\n"

    stop

    assert_equal true, closed
  end

  def test_after_reply_exception
    @server.app = lambda do |env|
      env['rack.after_reply'] << lambda { raise ArgumentError, "oops" }
      @simple.call(env)
    end

    @server.run

    skt = send_http "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    resp_hdrs, body = skt.read_response.split "\r\n\r\n", 2

    headers = header_hash resp_hdrs

    assert_equal "Hello", body
    assert_equal body.bytesize, headers["Content-Length"].to_i

    # When after_reply breaks the connection it will write the expected HTTP
    # response followed by a second HTTP response: HTTP/1.1 500
    #
    # This sleeps to give the server time to write the invalid/extra HTTP
    # response.
    #
    # * If we can read from the socket, we know that extra content has been
    #   written to the connection and assert that it's our erroneous 500
    #   response.
    # * If we would block trying to read from the socket, we can assume that
    #   the erroneous 500 response wasn't/won't be written.
    sleep 0.1
    assert_raises IO::WaitReadable do
      content = skt.read_nonblock(12)
      refute_includes content, "500"
    end

    stop
  end

  def test_rack_body_proxy
    closed = false
    body = Rack::BodyProxy.new(["Hello"]) { closed = true }

    @server.app = lambda { |env| [200, { "X-Header" => "Works" }, body] }

    @server.run

    send_http_read_response "GET /test HTTP/1.1\r\n\r\n"

    stop

    assert_equal true, closed
  end

  def test_rack_body_proxy_content_length
    str_ary = %w[0123456789 0123456789 0123456789 0123456789]
    str_ary_bytes = str_ary.sum(&:bytesize)

    body = Rack::BodyProxy.new(str_ary) { }

    @server.app = lambda { |env| [200, { "X-Header" => "Works" }, body] }

    @server.run

    resp = send_http_read_response "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n"

    resp_hdrs, body = resp.split RESP_SPLIT, 2

    headers = header_hash resp_hdrs

    stop

    if Rack.release.start_with? '1.'
      assert_equal "chunked", headers["Transfer-Encoding"]
    else
      assert_equal str_ary_bytes, headers["Content-Length"].to_i
    end
  end

  def test_common_logger
    log = StringIO.new

    logger = Rack::CommonLogger.new(@simple, log)

    @server.app = logger

    @server.run

    send_http_read_response "GET /test HTTP/1.1\r\n\r\n"

    stop

    assert_match %r!GET /test HTTP/1\.1!, log.string
  end

  def test_rack_chunked_array1
    body = [STR_1KB]
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    @server.app = rack_app
    @server.run

    resp = send_http_read_response "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n",
      decode_chunked: true

    resp_hdrs, resp_body = resp.split RESP_SPLIT, 2

    headers = header_hash resp_hdrs

    assert_equal 'chunked', headers['transfer-encoding']
    assert_equal STR_1KB, resp_body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_rack_chunked_array10
    body = Array.new 10, STR_1KB
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    @server.app = rack_app
    @server.run

    resp = send_http_read_response "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n",
      decode_chunked: true

    resp_hdrs, resp_body = resp.split RESP_SPLIT, 2

    headers = header_hash resp_hdrs

    assert_equal 'chunked', headers['transfer-encoding']
    assert_equal STR_1KB * 10, resp_body.force_encoding(Encoding::UTF_8)
  end if Rack.release < '3.1'

  def test_puma_enum
    body = Array.new(10, STR_1KB).to_enum
    app = lambda { |env| [200, { 'content-type' => 'text/plain; charset=utf-8' }, body] }
    rack_app = Rack::Chunked.new app
    @server.app = rack_app
    @server.run

    resp = send_http_read_response "GET /test HTTP/1.1\r\nConnection: Keep-Alive\r\n\r\n",
      decode_chunked: true

    resp_hdrs, resp_body = resp.split RESP_SPLIT, 2

    headers = header_hash resp_hdrs

    assert_equal 'chunked', headers['transfer-encoding']
    assert_equal STR_1KB * 10, resp_body.force_encoding(Encoding::UTF_8)
  end
end
