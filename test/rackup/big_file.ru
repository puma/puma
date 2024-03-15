static_file_path = File.join(Dir.tmpdir, "puma-static.txt")
File.write(static_file_path, "Hello World" * 100_000)

run lambda { |env|
  f = File.open(static_file_path)
  [200, {"content-type" => "text/plain", "content-length" => f.size.to_s}, f]
}
