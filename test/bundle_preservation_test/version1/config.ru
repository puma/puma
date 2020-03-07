run lambda { |env| [200, {'Content-Type'=>'text/plain'}, [ENV['BUNDLE_GEMFILE'].inspect]] }
