#\ -O bind=tcp://127.0.0.1:9292
run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
