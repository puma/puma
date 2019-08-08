run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello PATH #{ENV["PATH"]}"]] }
