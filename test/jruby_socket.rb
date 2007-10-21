
# Minimal test to help debug JRuby socket issues

require 'socket'
socket = TCPSocket.new('127.0.0.1', '3000')
socket.write("G")
socket.close_write
socket.write("E") 
