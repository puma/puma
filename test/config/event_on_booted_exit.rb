on_booted do
  pid = Process.pid
  Process.kill :TERM, pid
  begin
    Process.wait2 pid
  rescue Errno::ECHILD
  end
end
