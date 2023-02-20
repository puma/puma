on_booted do
  pid = Process.pid
  Process.kill :TERM, pid
  Process.wait pid
end
