# frozen_string_literal: true
# rackup file that can be

require 'securerandom'
require 'tmpdir'

fn_format = "#{Dir.tmpdir}/body_io_%04d.txt"

ary_hdrs = []
25.times { |i| ary_hdrs << ["X-My-Header-#{i}", SecureRandom.hex(25)] }
ary_hdrs << ['Content-Type', 'text/plain; charset=utf-8']
ary_hdrs.freeze

hdr_dly = 'HTTP_DLY'
hdr_body_conf = 'HTTP_BODY_CONF'

body_types = %w[a c i s].freeze

# length = 1018  bytesize = 1024
str_1kb = "──#{SecureRandom.hex 507}─\n".freeze

run lambda { |env|
  info = "#{Process.pid}\nHello World\n".dup

  if (dly = env[hdr_dly])
    sleep dly.to_f
    info << "Slept #{dly}\n"
  end

  body_conf = env[hdr_body_conf]

  if body_conf && body_conf.start_with?(*body_types)
    type = body_conf.slice!(0).to_sym
    len  = body_conf.to_i
  elsif body_conf
    type = :s
    len  = body_conf[/\d+\z/].to_i
  else    # default
    type = :s
    len  = 1
  end

  headers = ary_hdrs.to_h
  info_len_adj = 1023 - info.bytesize

  case type
  when :a      # body is an array
    body = Array.new len, str_1kb
    body[0] = info + body[0].byteslice(0, info_len_adj) + "\n"
    headers['Content-Length'] = (1024*len).to_s
  when :c      # body is chunked
    body = Enumerator.new do |yielder|
      yielder << info + str_1kb.byteslice(0, info_len_adj) + "\n"
      (len-1).times do |entry|
        yielder << str_1kb
      end
    end
  when :i      # body is an io
    headers['Content-Length'] = (1024*len).to_s
    fn = format fn_format, len
    body = File.open fn, 'rb'
  when :s      # body is a single string in an array
    info << str_1kb.byteslice(0, info_len_adj) << "\n" << (str_1kb * (len-1))
    headers['Content-Length'] = info.bytesize.to_s
    body = [info]
  end
  [200, headers, body]
}
