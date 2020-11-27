require_relative 'helpers/svr_in_proc'
require_relative 'helpers/sockets'

class TestHelpers < ::TestPuma::SvrInProc

  include TestPuma::Sockets

  def test_sockets_timeout
    start_server ci_test

    Thread.new {
      assert_raises (Timeout::Error) {
        connect_get_response dly: 1, timeout: 0.5
      }
    }.join
  end

  def ci_test
    require 'securerandom'

    # ~10k response is default

    env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : nil

    long_header_hash = {}

    25.times { |i| long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(25) }

    lambda { |env|
      resp = "#{Process.pid}\nHello World\n".dup

      if (dly = env['HTTP_DLY'])
        sleep dly.to_f
        resp << "Slept #{dly}\n"
      end

      # length = 1018  bytesize = 1024
      str_1kb = "──#{SecureRandom.hex 507}─\n"

      len = (env['HTTP_LEN'] || env_len || 10).to_i
      resp << (str_1kb * len)
      long_header_hash['Content-Type'] = 'text/plain; charset=UTF-8'
      long_header_hash['Content-Length'] = resp.bytesize.to_s
      [200, long_header_hash.dup, [resp]]
    }
  end
end
