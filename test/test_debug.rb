# Copyright (c) 2005 Zed A. Shaw 
# You can redistribute it and/or modify it under the same terms as Ruby.
#
# Additional work donated by contributors.  See http://puma.rubyforge.org/attributions.html 
# for more information.

require 'test/testhelp'
require 'puma/debug'

class PumaDbgTest < Test::Unit::TestCase

  def test_tracing_to_log
    FileUtils.rm_rf "log/puma_debug"

    PumaDbg::configure
    out = StringIO.new

    PumaDbg::begin_trace(:rails)
    PumaDbg::trace(:rails, "Good stuff")
    PumaDbg::end_trace(:rails)

    assert File.exist?("log/puma_debug"), "Didn't make logging directory"
  end

end
