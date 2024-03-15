run lambda { |env| [200, {"content-type" => "text/plain"}, [env["rack.url_scheme"]]] }
