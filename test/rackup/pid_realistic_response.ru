require 'securerandom'

long_header_hash = {}

25.times do |i|
  long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(25)
end

base = 'Puma ' * 2048

run lambda { |env|
  if (dly = env['REQUEST_PATH'][/sleep(\d+(\.\d+)?)\z/, 1])
    sleep dly.to_f
  end
  resp = "#{Process.pid}\nHello World\nslept#{dly}\n#{base}"
  [200, long_header_hash.dup, [resp]]
}
