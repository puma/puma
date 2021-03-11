app = lambda do |env|
  $stdout.write "hello\n"
  [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
end

run app
