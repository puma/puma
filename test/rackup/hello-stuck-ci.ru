run lambda { |env| sleep 10; [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
