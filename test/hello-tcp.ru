run lambda { |env, socket|
  p :here
  socket.puts "Sockets for the low, low price of free!"
  socket.close
}
