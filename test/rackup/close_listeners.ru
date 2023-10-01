require 'objspace'

run lambda { |env|
  ios = ObjectSpace.each_object(::TCPServer) { |svr| svr.close }
  [200, [], ["Found #{ios} TCPServer\n"]]
}
