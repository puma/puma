run lambda { |env| [200, {'content-type'=>'text/plain'}, [ENV['BUNDLE_GEMFILE'].inspect]] }
