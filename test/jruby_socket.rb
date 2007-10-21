
# Minimal test to help debug JRuby socket issues

require 'socket'

@server = Thread.new do 
  server_socket = TCPServer.new('0.0.0.0', 10101)
  this_client = server_socket.accept
  4.times do |n|
    begin
      data = this_client.readpartial(2)
      puts "Server got:  #{data}"
      if n == 0
        this_client.close 
        puts "Server closed the client"
      end
    rescue IOError => e
      puts "Server has: #{e.inspect}"
    end
    sleep(1)
  end
  server_socket.close
end

sleep(3)
client_socket = TCPSocket.new('0.0.0.0', 10101)
4.times do |n|
  string = "X#{n}"
  begin
    client_socket.write(string)
    puts "Client said: #{string}"
  rescue Errno::EPIPE => e
    puts "Client has: #{e.inspect}"
  end
  sleep(1)
end
client_socket.close

@server.join
