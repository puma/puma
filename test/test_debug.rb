require 'test/unit'
require 'mongrel/rails'
require 'mongrel/debug'
require 'fileutils'

class MongrelDbgTest < Test::Unit::TestCase

  def setup
    FileUtils.rm_rf "mongrel_debug"
    MongrelDbg::configure
  end

  def test_tracing_to_log
    MongrelDbg::begin_trace(:rails)
    MongrelDbg::trace(:rails, "Good stuff")
    MongrelDbg::end_trace(:rails)

    assert File.exist?("mongrel_debug"), "Didn't make logging directory"
    assert File.exist?("mongrel_debug/rails.log"), "Didn't make the rails.log file"
    assert File.size("mongrel_debug/rails.log") > 0, "Didn't write anything to the log."

    Class.report_object_creations
    Class.reset_object_creations
    Class.report_object_creations
  end

end
