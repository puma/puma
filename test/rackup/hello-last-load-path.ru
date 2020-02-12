run lambda { |env|
  [200, {}, [$LOAD_PATH[-1]]]
}
