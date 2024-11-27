# call with "GET /sleep<d> HTTP/1.1\r\n\r\n", where <d> is the number of
# seconds to sleep, can be a float or an int, returns process pid

regex_delay = /\A\/sleep(\d+(?:\.\d+)?)/
run lambda { |env|
  delay = (env['REQUEST_PATH'][regex_delay,1] || '0').to_f
  sleep delay
  [200, {"Content-Type" => "text/plain"}, ["Slept #{delay} #{Process.pid}"]]
}
