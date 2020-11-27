require 'securerandom'

ENC = Encoding::UTF_16LE

BYTE_ORDER_MARK = "\377\376".force_encoding ENC

run lambda { |env|
  hdrs = {}
  hdrs['Content-Type'] = 'text; charset=utf-16le'
  hdrs['Content-Disposition'] = 'attachment; filename="chunked_encoding.txt"'

  str_1kb = "──#{SecureRandom.hex 507}─\n"

  body = Enumerator.new do |yielder|
    yielder << BYTE_ORDER_MARK
    yielder << "#{Process.pid}\nHello World\n".encode(ENC)
    100.times do |entry|
      yielder << str_1kb.encode(ENC)
    end
    yielder << "\nHello World\n".encode(ENC)
  end

  [200, hdrs, body]
}
