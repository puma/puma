static_file_path = File.join(Dir.tmpdir, "puma-static.txt")
File.write(static_file_path, "Hello World" * 100_000)

run lambda { |env|
  f = File.open(static_file_path)
  [200, {"Content-Type" => "text/plain", "Content-Length" => f.size.to_s}, f]
}
