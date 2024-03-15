ENV["RAND"] ||= rand.to_s
run lambda { |env| [200, {"content-type" => "text/plain"}, ["Hello RAND #{ENV["RAND"]}"]] }
