# frozen_string_literal: true
# rackup file that can be

require 'securerandom'
require 'tmpdir'

fn_format = "#{Dir.tmpdir}/body_io_%04d.txt"

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : 1

ary_hdrs = []
25.times { |i| ary_hdrs << ["X-My-Header-#{i}", SecureRandom.hex(25)] }
ary_hdrs << ['Content-Type', 'text/plain; charset=utf-8']
ary_hdrs.freeze

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'

run lambda { |env|
  if (dly = env[hdr_dly])
    sleep dly.to_f
  end
  len = (t = env[hdr_body_conf]) ? t[/\d+\z/].to_i : env_len
  headers = ary_hdrs.to_h
  headers['Content-Length'] = (1024*len).to_s
  fn = format fn_format, len
  body = File.open fn
  [200, headers, body]
}
