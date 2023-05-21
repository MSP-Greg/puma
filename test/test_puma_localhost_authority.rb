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

  LHA_PATH = Localhost::Authority.path

  def setup
    @server = nil
    @host = "localhost"
    @lha_base = File.join Localhost::Authority.path, @host
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
    @server.run
  end

  def test_files_generated
    # Initiate server to create localhost authority
    unless File.exist? "#{@lha_base}.key"
      start_server
    end
    assert File.exist?("#{@lha_base}.key")
    assert File.exist?("#{@lha_base}.crt")
  end

  def test_self_signed
    start_server

    local_authority_crt =
      ::OpenSSL::X509::Certificate.new File.read("#{@lha_base}.crt")

    skt = send_http GET_11, ctx: new_ctx

    assert_equal local_authority_crt.to_pem, skt.peer_cert.to_pem
    assert_equal 'https', skt.read_body
  end
end if ::Puma::HAS_SSL &&  !Puma::IS_JRUBY
