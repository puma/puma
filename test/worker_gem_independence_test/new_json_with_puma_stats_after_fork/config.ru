require 'json'
run lambda { |env| [200, {'Content-Type'=>'text/plain'}, [JSON::VERSION]] }
