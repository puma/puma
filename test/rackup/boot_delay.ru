sleep 0.4

run lambda { |_env|
  [200, {"Content-Type" => "text/plain"}, ["Ready"]]
}
