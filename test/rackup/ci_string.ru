require 'securerandom'

env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : 10

headers = {}
25.times { |i| headers["X-My-Header-#{i}"] = SecureRandom.hex(25) }
headers['Content-Type'] = 'text/plain; charset=utf-8'

run lambda { |env|
  body = "#{Process.pid}\nHello World\n".dup

  if (dly = env['HTTP_DLY'])
    sleep dly.to_f
    body << "Slept #{dly}\n"
  end

  # length = 1018  bytesize = 1024
  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (env['HTTP_LEN'] || env_len).to_i
  body << (str_1kb * len)
  headers['Content-Length'] = body.bytesize.to_s
  [200, headers.dup, [body]]
}
