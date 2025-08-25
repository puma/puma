pidfile "t3-pid"
workers 3
before_worker_boot do |index|
  File.open("t3-worker-#{index}-pid", "w") { |f| f.puts Process.pid }
end
