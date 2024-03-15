run lambda { |env|
  sleep 0.001
  [200, {"content-type" => "text/plain"}, ["Hello World"]]
}
