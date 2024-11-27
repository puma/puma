hdrs = {'Content-Type'.freeze => 'text/plain'.freeze}.freeze
body = ['Hello World'.freeze].freeze
run lambda { |env| [200, hdrs.dup, body] }
