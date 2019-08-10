module TestApps

  # call with "GET /sleep<d> HTTP/1.1\r\n\r\n", where is the number of
  # seconds to sleep
  # same as rackup/sleep.ru
  SLEEP = -> (env) do
    dly = (env['REQUEST_PATH'][/\/sleep(\d+)/,1] || '0').to_i
    sleep dly
    [200, {"Content-Type" => "text/plain"}, ["Slept #{dly}"]]
  end

end
