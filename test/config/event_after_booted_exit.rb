after_booted do
  pid = Process.pid
  begin
    Process.kill :TERM, pid
  rescue Errno::ESRCH
  end

  begin
    Process.wait2 pid
  rescue Errno::ECHILD
  end
end
