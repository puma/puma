prune_bundler true
extra_runtime_dependencies ["rdoc"]
before_fork do
  puts "Last LOAD_PATH: #{$LOAD_PATH[-1]}"
end
