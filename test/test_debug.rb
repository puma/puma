# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://mongrel.rubyforge.org/attributions.html 
# for more information.

require 'fileutils'
FileUtils.mkdir_p "log/mongrel_debug"

require 'test/unit'
require 'mongrel/rails'
require 'mongrel/debug'


class MongrelDbgTest < Test::Unit::TestCase

  def setup
    FileUtils.rm_rf "log/mongrel_debug"
    MongrelDbg::configure
  end


  def test_tracing_to_log
    out = StringIO.new

    MongrelDbg::begin_trace(:rails)
    MongrelDbg::trace(:rails, "Good stuff")
    MongrelDbg::end_trace(:rails)

    assert File.exist?("log/mongrel_debug"), "Didn't make logging directory"
  end

end
