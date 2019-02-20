run lambda { |env|
  sleep 10
  [200, {}, ["Hello World"]]
}
