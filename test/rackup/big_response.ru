run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World" * 100_000]] }
