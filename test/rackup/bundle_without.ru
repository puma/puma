run lambda { |env| [200, {"Content-Type" => "text/plain"}, [ENV.fetch("BUNDLE_WITHOUT", "not_set")]] }
