require "localhost"
run proc { |env| [200, {"Content-Type" => "text/plain"}, [env['rack.url_scheme']]] }
