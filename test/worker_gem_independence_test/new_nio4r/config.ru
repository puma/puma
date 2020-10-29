run lambda { |env| [200, {'Content-Type'=>'text/plain'}, [NIO::VERSION]] }
