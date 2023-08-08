activate_control_app "tcp://0.0.0.0:9393"

app do |env|
  [200, {}, ["OK"]]
end
