# Mongrel Web Server - A Mostly Ruby Webserver and Library
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

require 'mongrel'


module Mongrel
  # Support for the Camping micro framework at http://camping.rubyforge.org
  # This implements the unusually long Postamble that Camping usually
  # needs and shrinks it down to just a single line or two.
  #
  # Your Postamble would now be:
  #
  #   Mongrel::Camping::start("0.0.0.0",3001,"/tepee",Tepee).join
  #
  # If you wish to get fancier than this then you can use the
  # Camping::CampingHandler directly instead and do your own
  # wiring:
  #
  #   h = Mongrel::HttpServer.new(server, port)
  #   h.register(uri, CampingHandler.new(Tepee))
  #   h.register("/favicon.ico", Mongrel::Error404Handler.new(""))
  #
  # I add the /favicon.ico since camping apps typically don't 
  # have them and it's just annoying anyway.
  module Camping

    # This is a specialized handler for Camping applications
    # that has them process the request and then translates
    # the results into something the Mongrel::HttpResponse
    # needs.
    class CampingHandler < Mongrel::HttpHandler
      def initialize(klass)
        @klass = klass
      end

      def process(request, response)
        controller = @klass.run(request.body, request.params)
        sendfile, clength = nil
        response.status = controller.status
        controller.headers.each do |k, v|
          if k =~ /^X-SENDFILE$/i
            sendfile = v
          elsif k =~ /^CONTENT-LENGTH$/i
            clength = v.to_i
          else
            [*v].each do |vi|
              response.header[k] = vi
            end
          end
        end

        if sendfile
          response.send_status(File.size(sendfile))
          response.send_header
          response.send_file(sendfile)
        elsif controller.body.respond_to? :read
          response.send_status(clength)
          response.send_header
          while chunk = controller.body.read(16384)
            response.write(chunk)
          end
          if controller.body.respond_to? :close
            controller.body.close
          end
        else
          body = controller.body.to_s
          response.send_status(body.length)
          response.send_header
          response.write(body)
        end
      end
    end

    # This is a convenience method that wires up a CampingHandler
    # for your application on a given port and uri.  It's pretty
    # much all you need for a camping application to work right.
    #
    # It returns the Mongrel::HttpServer which you should either
    # join or somehow manage.  The thread is running when 
    # returned.

    def Camping.start(server, port, uri, klass)
      h = Mongrel::HttpServer.new(server, port)
      h.register(uri, CampingHandler.new(klass))
      h.register("/favicon.ico", Mongrel::Error404Handler.new(""))
      h.run
      return h
    end
  end
end
