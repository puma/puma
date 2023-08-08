activate_control_app "tcp://0.0.0.0:9292"

app do |env|
  [200, {}, ["OK"]]
end

