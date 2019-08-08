run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello BUNDLE_GEMFILE #{ENV["BUNDLE_GEMFILE"]}"]] }
