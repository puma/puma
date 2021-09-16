require 'objspace'

run lambda { |env|
  ios = ObjectSpace.each_object(::TCPServer).to_a.tap { |a| a.each(&:close) }
  [200, [], ["#{ios.inspect}\n"]]
}
