# Mongrel Web Server - A Mostly Ruby Webserver and Library
#
# Copyright (C) 2005 Zed A. Shaw zedshaw AT zedshaw dot com
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

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
    assert File.exist?("log/mongrel_debug/rails.log"), "Didn't make the rails.log file"
    assert File.size("log/mongrel_debug/rails.log") > 0, "Didn't write anything to the log."
  end

end
