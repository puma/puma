prune_bundler true
extra_runtime_dependencies ["rdoc"]
before_fork do
  $LOAD_PATH.each do |path|
    puts "LOAD_PATH: #{path}"
  end
end
