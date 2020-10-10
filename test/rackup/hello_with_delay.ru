run lambda { |env|
  sleep 0.001
  [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
}
