
require 'rubygems'
require 'rack'
require 'rack/lobster'

def run(handler_name, n=1000, c=1)
  port = 7000
  
  server = fork do
    [STDOUT, STDERR].each { |o| o.reopen "/dev/null" }
      
    case handler_name
    when 'EMongrel'
      require 'swiftcore/evented_mongrel'
      handler_name = 'Mongrel'
    
    when 'Thin'
      require 'thin'
      hander_name = 'Thin'
    
    when 'gem' # Load the current Mongrel gem
      require 'mongrel'
      handler_name = 'Mongrel'
    
    when 'current' # Load the current Mongrel version under /lib
      require File.dirname(__FILE__) + '/../lib/mongrel'
      handler_name = 'Mongrel'
      
    end
    
    app = Rack::Lobster.new
    
    handler = Rack::Handler.const_get(handler_name)
    handler.run app, :Host => '0.0.0.0', :Port => port
  end

  sleep 2

  out = `nice -n20 ab -c #{c} -n #{n} http://127.0.0.1:#{port}/ 2> /dev/null`

  Process.kill('SIGKILL', server)
  Process.wait
  
  if requests = out.match(/^Requests.+?(\d+\.\d+)/)
    requests[1].to_i
  else
    0
  end
end

def benchmark(type, servers, request, concurrency_levels)
  send "#{type}_benchmark", servers, request, concurrency_levels
end

def graph_benchmark(servers, request, concurrency_levels)
  require '/usr/local/lib/ruby/gems/1.8/gems/gruff-0.2.9/lib/gruff'
  g = Gruff::Area.new
  g.title = "Server benchmark"
  
  servers.each do |server|
    g.data(server, concurrency_levels.collect { |c| print '.'; run(server, request, c) })
  end
  puts
  
  g.x_axis_label = 'Concurrency'
  g.y_axis_label = 'Requests / sec'
  g.labels = {}
  concurrency_levels.each_with_index { |c, i| g.labels[i] = c.to_s }
  
  g.write('bench.png')
  `open bench.png`
end

def print_benchmark(servers, request, concurrency_levels)
  puts 'server     request   concurrency   req/s'
  puts '=' * 42
  concurrency_levels.each do |c|
    servers.each do |server|
      puts "#{server.ljust(8)}   #{request}      #{c.to_s.ljust(4)}          #{run(server, request, c)}"
    end
  end
end