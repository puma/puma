ENV["RAND"] ||= rand.to_s
run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello RAND #{ENV["RAND"]}"]] }
