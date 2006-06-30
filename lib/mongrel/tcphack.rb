

# A modification proposed by Sean Treadway that increases the default accept
# queue of TCPServer to 1024 so that it handles more concurrent requests.
class TCPServer
   def initialize_with_backlog(*args)
     initialize_without_backlog(*args)
     listen(1024)
   end

   alias_method :initialize_without_backlog, :initialize
   alias_method :initialize, :initialize_with_backlog
end
