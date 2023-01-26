require "localhost"
run proc { [200, {"Content-Type" => "text/plain"}, ["Hello, World!"]] }
