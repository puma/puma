#
# Simple benchmark to compare Mongrel performance against
# other webservers supported by Rack.
#

require File.dirname(__FILE__) + '/utils'

libs = %w(current gem WEBrick EMongrel Thin)
libs = ARGV if ARGV.any?

benchmark "print", libs, 1000, [1, 10, 100]
