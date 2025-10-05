# frozen_string_literal: true

require_relative "helper"

require "puma/puma_http11"

class Http10ParserTest < PumaTest
  def test_parse_simple # rubocop:disable Minitest/MultipleAssertions
    parser = Puma::HttpParser.new
    req = {}
    http = "GET / HTTP/1.0\r\n\r\n"
    nread_ret  = parser.execute(req, http, 0)
    nread_meth = parser.nread

    assert_equal http.length, nread_ret, "Failed to parse the full HTTP request"
    assert_equal nread_meth , nread_ret, "Number read returned from execute does not match Parser#nread"

    assert_predicate parser, :finished?, "Parser didn't finish"
    refute_predicate parser, :error?   , "Parser had error"

    parser.reset
    assert_equal 0, parser.nread, "Number read after reset should be 0"
  end

  def test_parse_simple_req # rubocop:disable Minitest/MultipleAssertions
    parser = Puma::HttpParser.new
    req = {}
    http = "GET / HTTP/1.0\r\n\r\n"
    parser.execute(req, http, 0)

    assert_equal '/'       , req['REQUEST_PATH']
    assert_equal 'HTTP/1.0', req['SERVER_PROTOCOL']
    assert_equal '/'       , req['REQUEST_URI']
    assert_equal 'GET'     , req['REQUEST_METHOD']
    assert_nil req['FRAGMENT']
    assert_nil req['QUERY_STRING']
  end
end
