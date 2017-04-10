
run lambda { |env|
  io = env['rack.hijack'].call
  io.puts "HTTP/1.1 200\r\n\r\nBLAH"
  [-1, {}, []]
}
