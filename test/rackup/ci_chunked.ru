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

  str_1kb = "──#{SecureRandom.hex 507}─\n"

  len = (env['HTTP_LEN'] || env_len).to_i

  body = Enumerator.new do |yielder|
    yielder << resp
    len.times do |entry|
      yielder << str_1kb
    end
  end

  [200, headers.dup, body]
}
