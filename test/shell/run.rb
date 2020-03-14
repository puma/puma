require "puma"
require "puma/detect"

TESTS_TO_RUN = if Puma.jruby?
  %w[t1 t2]
else
  %w[t1 t2 t3]
end

results = TESTS_TO_RUN.map do |test|
  system("ruby -rrubygems test/shell/#{test}.rb ") # > /dev/null 2>&1
end

if results.any? { |r| r != true }
  exit 1
else
  exit 0
end
