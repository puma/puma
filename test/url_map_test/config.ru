map "/ok" do
  run ->(env) { [200, {}, ["OK"]] }
end
