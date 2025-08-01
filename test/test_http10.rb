# frozen_string_literal: true

require_relative "helper"

require "puma/puma_http11"

class Http10ParserTest < PumaTest
  def test_parse_simple
    parser = Puma::HttpParser.new
    req = {}
    http = "GET / HTTP/1.0\r\n\r\n"
    nread = parser.execute(req, http, 0)

    assert nread == http.length, "Failed to parse the full HTTP request"
    assert parser.finished?, "Parser didn't finish"
    assert !parser.error?, "Parser had error"
    assert nread == parser.nread, "Number read returned from execute does not match"

    assert_equal '/', req['REQUEST_PATH']
    assert_equal 'HTTP/1.0', req['SERVER_PROTOCOL']
    assert_equal '/', req['REQUEST_URI']
    assert_equal 'GET', req['REQUEST_METHOD']
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']

    parser.reset
    assert parser.nread == 0, "Number read after reset should be 0"
  end
end
