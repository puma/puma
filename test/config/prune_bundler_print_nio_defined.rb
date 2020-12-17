prune_bundler true
before_fork do
  puts "defined?(::NIO): #{defined?(::NIO).inspect}"
end
