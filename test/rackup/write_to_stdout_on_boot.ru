puts "Loading app"
run lambda { |env| [200, {"content-type" => "text/plain"}, ["Hello World"]] }
