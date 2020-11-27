# frozen_string_literal: true

require_relative 'helper'
require_relative 'helpers/svr_popen'

# These tests are used to verify that Puma works with SSL sockets.  Only
# integration tests isolate the server from the test environment, so there
# should be a few SSL tests.
#
# Other tests make use of 'client' SSLSockets created by net/http,
# and OpenSSL is loaded in the CI process.  By shelling out with IO.popen,
# the server process isn't affected by whatever is loaded in the CI process.

class TestPOpenSSL < ::TestPuma::SvrPOpen

  require 'openssl'

  # this checks an ssl binder configured with `ssl_bind` and also verifies that
  # OpenSSL is not loaded in Puma's process
  #
  def test_openssl_not_loaded
    skip_unless :mri
    skip 'Skip old Windows' if ::Puma.windows? && RUBY_VERSION < '2.4'
    setup_puma :ssl, config: <<RUBY
app do |env|
  ssl = env['rack.url_scheme'] + ' ' + (Object.const_defined? :OpenSSL).to_s
  [200, {}, [ssl]]
end
RUBY

    ctrl_type :tcp
    start_puma '-q'
    assert_equal 'https false', connect_get_body
  end
end if ::Puma.ssl?
