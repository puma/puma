run lambda { |env|
  30000000.times { }
  [200, {}, ["Hello World"]]
}
