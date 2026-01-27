sleep 0.2

run lambda { |_env|
  [200, {"Content-Type" => "text/plain"}, ["Ready"]]
}
