run lambda { |env|
  p :body => env['rack.input'].read
  [200, {"Content-Type" => "text/plain"}, ["Hello World"]]
}
