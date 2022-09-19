workers 2

on_worker_boot(:test) do |index, data|
  data[:test] = index
end

on_worker_shutdown(:test) do |index, data|
  File.write "hook_data-#{index}.txt", "index #{index} data #{data[:test]}", mode: 'wb:UTF-8'
end
