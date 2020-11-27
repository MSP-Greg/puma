# dumps rack env to body

run lambda { |env|
  body = ''.dup
  env.sort.each { |a| body << "#{a.first}: #{a[1]}\n" }
  [200, {}, [body]]
}
