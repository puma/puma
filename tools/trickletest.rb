require 'socket'
require 'stringio'

def do_test(st, chunk)
  s = TCPSocket.new('127.0.0.1',ARGV[0].to_i);
  req = StringIO.new(st)
  
  while data = req.read(chunk)
    puts "write #{data.length}: '#{data}'"
    s.write(data)
    s.flush
    sleep 0.1
  end
  s.close
end


st = "GET / HTTP/1.1\r\nHost: www.zedshaw.com\r\nContent-Type: text/plain\r\n\r\n"

threads = []
ARGV[1].to_i.times do 
  threads << Thread.new do
    (st.length - 1).times do |chunk|
      puts ">>>> #{chunk+1} sized chunks"
      do_test(st, chunk+1)
    end

    1000.times do 
      do_test(st, rand(st.length) + 1)
    end
    
  end

  sleep(1+rand)
end

threads.each {|t| t.join}
