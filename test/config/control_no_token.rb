activate_control_app 'unix:///tmp/pumactl.sock', { no_token: true }

app do |env|
  [200, {}, ["embedded app"]]
end
