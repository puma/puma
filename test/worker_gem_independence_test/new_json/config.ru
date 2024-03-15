require 'json'
run lambda { |env| [200, {'content-type'=>'text/plain'}, [JSON::VERSION]] }
