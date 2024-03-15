hdrs = {'content-type'.freeze => 'text/plain'.freeze}.freeze
body = ['Hello World'.freeze].freeze
run lambda { |env| [200, hdrs, body] }
