# call with "GET /sleep<d>-<s> HTTP/1.1\r\n\r\n", where <d> is the number of
# seconds to sleep and <s> is the step

run lambda { |env|
  p = env['REQUEST_PATH']
  dly = (p[/\/sleep(\d+)/,1] || '0').to_i
  step = p[/(\d+)\z/,1].to_i
  sleep dly
  [200, {"Content-Type" => "text/plain"}, ["Slept #{dly} #{step}"]]
}
