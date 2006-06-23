# Mongrel Web Server - A Mostly Ruby HTTP server and Library
#
# Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA


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
