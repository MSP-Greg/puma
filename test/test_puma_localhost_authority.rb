# Nothing in this file runs if Puma isn't compiled with ssl support
#
# helper is required first since it loads Puma, which needs to be
# loaded so HAS_SSL is defined
require_relative "helper"
require "localhost/authority"

if ::Puma::HAS_SSL && !Puma::IS_JRUBY
  require "puma/minissl"
  require_relative "helpers/puma_socket"

  require "openssl" unless Object.const_defined? :OpenSSL
end

class TestPumaLocalhostAuthority < Minitest::Test
  parallelize_me!

  include TestPuma::PumaSocket

  def setup
    @server = nil
    @host = "localhost"
    start_server
  end

  def teardown
    @server&.stop true
  end

  # yields ctx to block, use for ctx setup & configuration
  def start_server
    app = lambda { |env| [200, {}, [env['rack.url_scheme']]] }

    @log_writer = SSLLogWriterHelper.new STDOUT, STDERR
    @server = Puma::Server.new app, nil, {log_writer: @log_writer}
    @server.add_ssl_listener @host, 0, nil
    @tcp_port = @server.connected_ports[0]
    @ctx = @server.binder.ios[0].instance_variable_get :@ctx
    @server.run
  end

  def test_files_generated
    assert File.exist?(@ctx.cert)
    assert File.exist?(@ctx.key)
  end

  def test_self_signed
    local_authority_crt = ::OpenSSL::X509::Certificate.new File.read(@ctx.cert)

    skt = send_http GET_11, ctx: new_ctx

    assert_equal local_authority_crt.to_pem, skt.peer_cert.to_pem
    assert_equal 'https', skt.read_body
  end
end if ::Puma::HAS_SSL &&  !Puma::IS_JRUBY
