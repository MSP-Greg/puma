require_relative "helper"
require_relative "helpers/test_puma/puma_socket"
require "puma/events"
require "puma/server"
require "nio"
require "ipaddr"

class WithoutBacktraceError < StandardError
  def backtrace; nil; end
  def message; "no backtrace error"; end
end

class TestPumaServerErr < Minitest::Test
#  parallelize_me!

  include TestPuma
  include TestPuma::PumaSocket

  STATUS_CODES = ::Puma::HTTP_STATUS_CODES

  HEADERS_413 = [
    "Connection: close",
    "Content-Length: #{STATUS_CODES[413].bytesize}"
  ]

  HOST = HOST4

  def setup
    STDOUT.syswrite "\n" if ENV['PUMA_DEBUG_CLIENT_READ'] == 'true'
    @host = HOST
    @app = ->(env) { [200, {}, [env['rack.url_scheme']]] }

    @log_writer = Puma::LogWriter.strings
    @events = Puma::Events.new
    @server = Puma::Server.new @app, @events, {log_writer: @log_writer}
  end

  def teardown
    @server.stop(true)
    STDOUT.syswrite "\n" if ENV['PUMA_DEBUG_CLIENT_READ'] == 'true'
    # Errno::EBADF raised on macOS
  end

  def server_run(**options, &block)
    options[:log_writer]  ||= @log_writer
    options[:min_threads] ||= 1
    @server = Puma::Server.new block || @app, @events, options
    @bind_port = (@server.add_tcp_listener @host, 0).addr[1]
    @server.run
  end

  # Sets the server to have a http_content_length_limit of 190 kB, then sends a
  # 200 kB body with Content-Length set to the same.
  # Verifies that the connection is closed properly.
  def test_http_11_keep_alive_req_large_content_length
    lleh_called = false
    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * 200_000
    server_run(http_content_length_limit: 190_000, lowlevel_error_handler: lleh) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\nContent-Length: 200000\r\n\r\n" \
      "#{long_string}"

    response = socket.read_response

    # Content Too Large
    assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
    assert_equal HEADERS_413, response.headers

    sleep 0.5
    refute lleh_err
    assert_raises(Errno::ECONNRESET) { socket << GET_11 }
  end

  # Sets the server to have a http_content_length_limit of 100 kB, then sends a
  # 200 kB chunked body.  Verifies that the connection is closed properly.
  def test_http_11_keep_alive_req_large_chunked
    chunk_length = 20_000
    chunk_part_qty = 10
    req_body_length = chunk_length * chunk_part_qty

    lleh_called = false
    lleh_err = nil

    lleh = -> (err) {
      lleh_err = err
      [500, {'Content-Type' => 'text/plain'}, ['error']]
    }
    long_string = 'a' * chunk_length
    long_string_part = "#{long_string.bytesize.to_s 16}\r\n#{long_string}\r\n"
    long_chunked = "#{long_string_part * chunk_part_qty}0\r\n\r\n"

    server_run(
      http_content_length_limit: 100_000,
      lowlevel_error_handler: lleh
    ) { [200, {}, ['Hello World']] }

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n" \
      "Transfer-Encoding: chunked\r\n\r\n#{long_chunked}"

    response = socket.read_response

    # Content Too Large
    assert_equal "HTTP/1.1 413 #{STATUS_CODES[413]}", response.status
    assert_equal HEADERS_413, response.headers

    sleep 0.5
    refute lleh_err

    assert_raises(Errno::ECONNRESET) { socket << GET_11 }
  end

  # # sends a request with a 200 kB chunked body
  # and continues with another simple GET request
  def test_chunked_request
    chunk_length = 20_000
    chunk_part_qty = 10
    req_body_length = chunk_length * chunk_part_qty
    body = nil
    content_length = nil
    transfer_encoding = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      transfer_encoding = env['HTTP_TRANSFER_ENCODING']
      [200, {}, [""]]
    }

    long_string = 'a' * chunk_length
    long_string_part = "#{long_string.bytesize.to_s 16}\r\n#{long_string}\r\n"
    long_chunked = "#{long_string_part * chunk_part_qty}0\r\n\r\n"

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n" \
      "Transfer-Encoding: chunked\r\n\r\n#{long_chunked}"

    response = socket.read_response

    assert_equal req_body_length.to_s, content_length
    assert_equal long_string * chunk_part_qty, body
    assert_nil transfer_encoding

    response = socket.req_write(GET_11).read_response
    assert_equal "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", response
  end

  # sends a request with a 200 kB standard body,
  # and continues with another simple GET request
  def test_body_request
    req_body_length = 200_000
    body = nil
    content_length = nil
    transfer_encoding = nil
    server_run { |env|
      body = env['rack.input'].read
      content_length = env['CONTENT_LENGTH']
      transfer_encoding = env['HTTP_TRANSFER_ENCODING']
      [200, {}, [""]]
    }

    long_string = 'a' * req_body_length

    socket = send_http "GET / HTTP/1.1\r\nConnection: Keep-Alive\r\n" \
      "Content-Length: #{req_body_length}\r\n\r\n#{long_string}"

    response = socket.read_response

    assert_equal req_body_length.to_s, content_length
    assert_equal long_string, body
    assert_nil transfer_encoding

    response = socket.req_write(GET_11).read_response
    assert_equal "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n", response
  end
end
