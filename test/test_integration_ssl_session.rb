# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/integration'
require_relative 'helpers/puma_socket'

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSockets created by
# net/http, OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSLSession < TestIntegration
  # parallel seems to run fine locally
  parallelize_me! if ::Puma::IS_MRI && !ENV['GITHUB_ACTIONS']

  require "openssl" unless defined?(::OpenSSL::SSL)

  include TestPuma::PumaSocket

  OSSL = ::OpenSSL::SSL

  CLIENT_HAS_TLS1_3 = OSSL.const_defined? :TLS1_3_VERSION

  GET = "GET / HTTP/1.1\r\nConnection: close\r\n\r\n"

  RESP = "HTTP/1.1 200 OK\r\nConnection: close\r\nContent-Length: 5\r\n\r\nhttps"

  CERT_PATH = File.expand_path "../examples/puma/client-certs", __dir__

  def teardown
    return if skipped?
    cli_pumactl 'stop'
    assert wait_for_server_to_include 'Goodbye!'
    @server.close unless @server.is_a?(IO) && @server.closed?
    @server = nil
    super
  end

  def set_reuse(reuse)
    <<~CONFIG
      ssl_bind '#{HOST}', 0, {
        cert: '#{CERT_PATH}/server.crt',
        key:  '#{CERT_PATH}/server.key',
        ca:   '#{CERT_PATH}/ca.key',
        verify_mode: 'none',
        reuse: #{reuse}
      }

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    CONFIG
  end

  def with_server(config)
    cli_server set_pumactl_args, config: config, config_bind: true
    yield
  end

  def run_session(reuse, tls = nil)
    config = set_reuse reuse

    with_server(config) { ssl_client tls_vers: tls }
  end

  def test_dflt
    reused = run_session true
    assert reused, 'session was not reused'
  end

  def test_dflt_tls1_2
    reused = run_session true, :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_dflt_tls1_3
    skip 'TLSv1.3 unavailable' unless Puma::MiniSSL::HAS_TLS1_3 && CLIENT_HAS_TLS1_3
    reused = run_session true, :TLS1_3
    assert reused, 'session was not reused'
  end

  def test_1000_tls1_2
    reused = run_session '{size: 1_000}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_1000_10_tls1_2
    reused = run_session '{size: 1000, timeout: 10}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test__10_tls1_2
    reused = run_session '{timeout: 10}', :TLS1_2
    assert reused, 'session was not reused'
  end

  def test_off_tls1_2
    ssl_vers = Puma::MiniSSL::OPENSSL_LIBRARY_VERSION
    old_ssl = ssl_vers.include?(' 1.0.') || ssl_vers.match?(/ 1\.1\.1[ a-e]/)
    skip 'Requires 1.1.1f or later' if old_ssl
    reused = run_session 'nil', :TLS1_2
    assert reused, 'session was not reused'
  end

  # TLSv1.3 reuse is always on
  def test_off_tls1_3
    skip 'TLSv1.3 unavailable' unless Puma::MiniSSL::HAS_TLS1_3 && CLIENT_HAS_TLS1_3
    reused = run_session 'nil'
    assert reused, 'TLSv1.3 session was not reused'
  end

  def client_ctx(tls_vers = nil)
    ctx = OSSL::SSLContext.new
    ctx.verify_mode = OSSL::VERIFY_NONE
    ctx.session_cache_mode = OSSL::SSLContext::SESSION_CACHE_CLIENT
    if tls_vers
      if ctx.respond_to? :max_version=
        ctx.max_version = tls_vers
        ctx.min_version = tls_vers
      else
        ctx.ssl_version = tls_vers.to_s.sub('TLS', 'TLSv').to_sym
      end
    end
    ctx
  end

  def ssl_client(tls_vers: nil)
    ctx = client_ctx tls_vers
    skt1 = send_http GET, ctx: ctx

    assert_equal RESP, skt1.read_response
    # don't hold reference to skt1.session
    shared_session = OSSL::Session.new skt1.session.to_pem

    ctx = client_ctx tls_vers
    skt2 = send_http GET, ctx: ctx, session: shared_session
    assert_equal RESP, skt2.read_response

    skt2.session_reused?
  end
end if Puma::HAS_SSL && Puma::IS_MRI
