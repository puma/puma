sleep 10

run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
