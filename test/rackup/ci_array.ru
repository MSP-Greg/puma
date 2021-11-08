# frozen_string_literal: true
require 'securerandom'

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : 1

ary_hdrs = []
25.times { |i| ary_hdrs << ["X-My-Header-#{i}", SecureRandom.hex(25)] }
ary_hdrs << ['Content-Type', 'text/plain; charset=utf-8']
ary_hdrs.freeze

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'

run lambda { |env|
  body0 = "#{Process.pid}\nHello World\n".dup

  if (dly = env[hdr_dly])
    sleep dly.to_f
    body0 << "Slept #{dly}\n"
  end

  # length = 1018  bytesize = 1024
  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (t = env[hdr_body_conf]) ? t[/\d+\z/].to_i : env_len

  body0 = (body0 + str_1kb).byteslice(0,1023) + "\n"

  body = Array.new len, str_1kb
  body[0] = body0
  headers = ary_hdrs.to_h
  headers['Content-Length'] = (1024*len).to_s
  [200, headers, body]
}
