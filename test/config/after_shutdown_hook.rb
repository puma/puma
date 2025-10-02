workers 2

after_worker_shutdown do |worker|
  STDOUT.syswrite "\nafter_worker_shutdown worker=#{worker.index} status=#{worker.process_status.to_i}"
end
