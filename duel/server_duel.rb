# frozen_string_literal: true

require_relative "duel_helper"

# Whole requests through Puma::Server#process_client, as a pool thread
# runs it for each connection: reading and parsing the request, calling
# the Rack app, writing its response, and keep-alive. The server is
# started with no listeners, which gives it its thread pool and reactor,
# and each benchmark hands it connections itself, as its accept loop
# would. The pool's one thread waits idle the whole time, so a pipelined
# request is handled inline, as Puma does when it has a thread to spare.

HELLO_APP = ->(_env) { [200, { "content-type" => "text/plain" }, ["Hello World"]] }

ECHO_APP = lambda do |env|
  body = env["rack.input"].read
  [201, { "content-type" => "application/json" }, [body]]
end

def start_server(app)
  @server = Puma::Server.new(app, nil, server_options)
  @server.run
end

def stop_server
  @server.stop(true)
end

# Serves the request on a new connection, from memory.
def serve(socket)
  @server.process_client(nil, @server.new_client(socket.rewind, nil))
end

duel "server: a GET on a new connection",
     setup: -> { start_server(HELLO_APP) }, teardown: -> { stop_server } do
  once { @socket = MemorySocket.new(http_request("GET", "/", headers: curl_headers.merge("Connection" => "close"))) }
  serve(@socket)
end

duel "server: a browser's GET",
     setup: -> { start_server(HELLO_APP) }, teardown: -> { stop_server } do
  once do
    headers = browser_headers.merge("Connection" => "close")
    @socket = MemorySocket.new(http_request("GET", "/dashboard/projects/42?tab=activity", headers: headers))
  end
  serve(@socket)
end

duel "server: a POST that the app reads",
     setup: -> { start_server(ECHO_APP) }, teardown: -> { stop_server } do
  once do
    headers = api_headers.merge("Connection" => "close")
    @socket = MemorySocket.new(http_request("POST", "/api/v1/users", headers: headers, body: json_document(10)))
  end
  serve(@socket)
end

duel "server: 10 keep-alive requests on one connection",
     setup: -> { start_server(HELLO_APP) }, teardown: -> { stop_server } do
  once do
    last = http_request("GET", "/", headers: curl_headers.merge("Connection" => "close"))
    @socket = MemorySocket.new((http_request("GET", "/", headers: curl_headers) * 9) + last)
  end
  serve(@socket)
end

# Over a real TCP connection on the loopback interface, accepted and
# served from the benchmark's own thread. System calls time too
# unsteadily, so this is judged on its counts alone.
duel "server: a GET over a loopback TCP connection", judge: :counted,
     setup: -> { start_server(HELLO_APP) }, teardown: -> { @listener.close && stop_server } do
  once do
    @listener = TCPServer.new("127.0.0.1", 0)
    @port = @listener.addr[1]
    @request = http_request("GET", "/", headers: curl_headers.merge("Connection" => "close"))
  end
  socket = TCPSocket.new("127.0.0.1", @port)
  socket.write(@request)
  @server.process_client(nil, @server.new_client(@listener.accept, nil))
  socket.read
  socket.close
end
