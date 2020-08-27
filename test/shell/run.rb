require "puma"
require "puma/detect"

return unless Process.respond_to?(:fork)

if system("ruby test/shell/t3.rb ")
  exit 0
else
  exit 1
end
