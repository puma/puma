# call with "GET /sleep<d>-<s> HTTP/1.1\r\n\r\n", where <d> is the number of
# seconds to sleep (can be a float or an int) and <s> is the step

regex_delay = /\A\/sleep(\d+(?:\.\d+)?)/
run lambda { |env|
  p = env['REQUEST_PATH']
  delay = (p[regex_delay,1] || '0').to_f
  step = p[/(\d+)\z/,1].to_i
  sleep delay
  [200, {"Content-Type" => "text/plain"}, ["Slept #{delay} #{step}"]]
}
