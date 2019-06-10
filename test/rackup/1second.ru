run lambda { |env|
  sleep 1
  [200, {}, ["Hello World"]]
}
