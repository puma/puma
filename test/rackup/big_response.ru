big_array = 100_000.times.map { "Hello World" }

run lambda { |env| [200, {"Content-Type" => "text/plain"}, big_array] }
