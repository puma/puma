
require 'http11'

request_data = "GET /events/show/2 HTTP/1.1\r\n\r\nfield1=value1&field2=value2&field3=value3"
request_data += ("X" * (16 * 1024 - request_data.size))

parser = Mongrel::HttpParser.new
parser.reset
params = {}
nread = parser.execute(params, request_data, 0)
puts "finished=#{parser.finished?}"
nread = parser.execute(params, request_data, nread)

puts "params="
params.each {|k,v| puts "  #{k} = #{v}"}
puts "nread=#{nread}"
puts "error?=#{parser.error?}"
puts "finished=#{parser.finished?}"
puts "nread=#{parser.nread}"

puts request_data[parser.nread..-1]
