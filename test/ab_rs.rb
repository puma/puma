url = ARGV.shift
count = (ARGV.shift || 1000).to_i

STDOUT.sync = true

1.upto(5) do |i|
  print "#{i}: "
  str = `ab -n #{count} -c #{i} #{url} 2>/dev/null`

  rs = /Requests per second:\s+([\d.]+)\s/.match(str)
  puts rs[1]
end

puts "Keep Alive:"

1.upto(5) do |i|
  print "#{i}: "
  str = `ab -n #{count} -k -c #{i} #{url} 2>/dev/null`

  rs = /Requests per second:\s+([\d.]+)\s/.match(str)
  puts rs[1]
end
