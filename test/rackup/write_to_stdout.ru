app = lambda do |env|
  $stdout.write "hello\n"
  [200, {"content-type" => "text/plain"}, ["Hello World"]]
end

run app
