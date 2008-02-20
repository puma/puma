# Benchmark to compare Mongrel performance against
# previous Mongrel version (the one installed as a gem).
#
# Run with:
#
#  ruby previous.rb [num of request]
#

require File.dirname(__FILE__) + '/utils'

benchmark "print", %w(current gem), 1000, [1, 10, 100]
