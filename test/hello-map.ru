map "/foo" do
  run lambda { |env| [200, {"Content-Type" => "text/plain"}, ["Hello World"]] }
end
