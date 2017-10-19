results = %w[t1 t2 t3].map do |test|
  system("ruby -rrubygems test/shell/#{test}.rb ") # > /dev/null 2>&1
end

if results.any? { |r| r != true }
  exit 1
else
  exit 0
end
