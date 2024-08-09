workers 2

before_worker_boot(:test) do |index, data|
  data[:test] = index
end

on_worker_shutdown(:test) do |index, data|
  STDOUT.syswrite "\nindex #{index} data #{data[:test]}"
end
