on_booted { puts "never called" }

app do |env|
  [200, {}, ["embedded app"]]
end
