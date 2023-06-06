hdrs = {'content-type' => 'text/plain'}
body = ['Hello World'.freeze].freeze
run lambda { |env| [200, hdrs, body] }
