run lambda { |env| [200, {"Content-Type" => "text/plain"}, [env["rack.url_scheme"]]] }
