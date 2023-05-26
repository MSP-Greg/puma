# frozen_string_literal: true

require_relative 'helper'
require_relative "helpers/integration"
require_relative "helpers/puma_socket"

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# For instance, since other tests make use of 'client' SSLSockets created by
# net/http, OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestIntegrationSSL < TestIntegration
  parallelize_me! if ::Puma.mri?

  include TestPuma::PumaSocket

  require "openssl"

  CERT_PATH = File.expand_path '../examples/puma', __dir__

  def setup
    @tcp_port = UniquePort.call
    @control_tcp_port = UniquePort.call
  end

  def teardown
    return if skipped?
    cli_pumactl 'stop'
    assert wait_for_server_to_include('Goodbye!')

    @server.close if @server && !@server.closed?
    @server = nil
  end

  def test_ssl_run
    config = <<~RUBY
      if ::Puma.jruby?
        ssl_bind '#{HOST}', '#{@tcp_port}', {
          keystore: '#{CERT_PATH}/keystore.jks',
          keystore_pass:  'jruby_puma',
          verify_mode: 'none'
        }
      else
        key  = '#{CERT_PATH}/puma_keypair.pem'
        cert = '#{CERT_PATH}/cert_puma.pem'

        ssl_bind '#{HOST}', '#{@tcp_port}', {
          cert: cert,
          key:  key,
          verify_mode: 'none'
        }
      end

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    body = send_http_read_resp_body GET_11, ctx: new_ctx
    assert_equal 'https', body
  end

  def test_verify_client_cert_roundtrip
    cert_path = File.expand_path '../examples/puma/client-certs', __dir__

    config = <<~RUBY
      if ::Puma::IS_JRUBY
        ssl_bind '#{HOST}', '#{@tcp_port}', {
          keystore: '#{cert_path}/keystore.jks',
          keystore_pass: 'jruby_puma',
          verify_mode: 'force_peer'
        }
      else
        ssl_bind '#{HOST}', '#{@tcp_port}', {
          cert: '#{cert_path}/server.crt',
          key:  '#{cert_path}/server.key',
          ca:   '#{cert_path}/ca.crt',
          verify_mode: 'force_peer'
        }
      end
      threads 1, 5

      app do |env|
        [200, {}, [env['puma.peercert'].to_s]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    body = send_http_read_resp_body GET_11, host: HOST,
      ctx: new_ctx { |c|
        ca   = "#{cert_path}/ca.crt"
        cert = "#{cert_path}/client.crt"
        key  = "#{cert_path}/client.key"
        c.ca_file = ca
        c.cert = ::OpenSSL::X509::Certificate.new File.read(cert)
        c.key  = ::OpenSSL::PKey::RSA.new File.read(key)
        if c.respond_to? :max_version=
          c.max_version = :TLS1_2
        else
          c.ssl_version = :TLSv1_2
        end
        c.verify_mode = ::OpenSSL::SSL::VERIFY_PEER
      }

    assert_equal File.read("#{cert_path}/client.crt"), body
  end

  def test_ssl_run_with_pem
    skip_if :jruby

    config = <<~RUBY
      key  = '#{CERT_PATH}/puma_keypair.pem'
      cert = '#{CERT_PATH}/cert_puma.pem'

      ssl_bind '#{HOST}', '#{@tcp_port}', {
        cert_pem: File.read(cert),
        key_pem:  File.read(key),
        verify_mode: 'none'
      }

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    skt = send_http GET_11, ctx: new_ctx
    body = skt.read_body

    svr_pem = File.read "#{CERT_PATH}/cert_puma.pem"

    assert_equal svr_pem, skt.peer_cert.to_pem
    assert_equal 'https', body
  end

  def test_ssl_run_with_localhost_authority
    skip_if :jruby

    config = <<~RUBY
      require 'localhost'
      ssl_bind '#{HOST}', '#{@tcp_port}'

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    body = send_http_read_resp_body GET_11, ctx: new_ctx
    assert_equal 'https', body
  end

  def test_ssl_run_with_encrypted_key
    skip_if :jruby

    config = <<~RUBY
      key_path  = '#{File.expand_path '../examples/puma/encrypted_puma_keypair.pem', __dir__}'
      cert_path = '#{File.expand_path '../examples/puma/cert_puma.pem', __dir__}'
      key_command = ::Puma::IS_WINDOWS ? 'echo hello world' :
        '#{File.expand_path '../examples/puma/key_password_command.sh', __dir__}'

      ssl_bind '#{HOST}', '#{@tcp_port}', {
        cert: cert_path,
        key: key_path,
        verify_mode: 'none',
        key_password_command: key_command
      }

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    body = send_http_read_resp_body GET_11, ctx: new_ctx
    assert_equal 'https', body
  end

  def test_ssl_run_with_encrypted_pem
    skip_if :jruby

    config = <<~RUBY
      key_path  = '#{CERT_PATH}/encrypted_puma_keypair.pem'
      cert_path = '#{CERT_PATH}/cert_puma.pem'
      key_command = ::Puma::IS_WINDOWS ? 'echo hello world' :
        '#{CERT_PATH}/key_password_command.sh'

      ssl_bind '#{HOST}', '#{@tcp_port}', {
        cert_pem: File.read(cert_path),
        key_pem: File.read(key_path),
        verify_mode: 'none',
        key_password_command: key_command
      }

      app do |env|
        [200, {}, [env['rack.url_scheme']]]
      end
    RUBY

    cli_server set_pumactl_args, config: config, config_bind: true

    body = send_http_read_resp_body GET_11, ctx: new_ctx
    assert_equal 'https', body
  end
end if ::Puma::HAS_SSL
