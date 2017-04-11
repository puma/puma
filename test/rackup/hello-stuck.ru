run lambda { |env| sleep 60; [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
