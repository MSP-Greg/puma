require 'securerandom'

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : 10

headers = {}
25.times { |i| headers["X-My-Header-#{i}"] = SecureRandom.hex(25) }
headers['Content-Type'] = 'text/plain; charset=utf-8'

run lambda { |env|
  resp = "#{Process.pid}\nHello World\n".dup

  if (dly = env['HTTP_DLY'])
    sleep dly.to_f
    resp << "Slept #{dly}\n"
  end

  # length = 1018  bytesize = 1024
  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (env['HTTP_LEN'] || env_len).to_i

  ary = Array.new len+1, str_1kb
  ary[0] = resp

  headers['Content-Length'] = (resp.bytesize + 1024*len).to_s
  [200, headers.dup, ary]
}
