worker_shutdown_timeout 0

before_fork do
  pid = fork do
    sleep 30 # This has to exceed the test timeout
  end

  pid_filename = File.join(Dir.tmpdir, 'process_detach_test.pid')
  File.write(pid_filename, pid)
  Process.detach(pid)
end
