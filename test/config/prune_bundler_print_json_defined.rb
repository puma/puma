prune_bundler true
before_fork do
  puts "defined?(JSON): #{defined?(JSON).inspect}"
end
