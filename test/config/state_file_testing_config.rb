pidfile "t3-pid"
workers 3
on_worker_boot do |index|
  File.open("t3-worker-#{index}-pid", "w") { |f| f.puts Process.pid }
end

before_fork { 1 }
on_worker_shutdown { 1 }
on_worker_boot { 1 }
on_worker_fork { 1 }
on_restart { 1 }
after_worker_boot { 1 }
lowlevel_error_handler { 1 }
