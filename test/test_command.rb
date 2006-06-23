# Mongrel Web Server - A Mostly Ruby HTTP server and Library
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

require 'test/unit'
require 'mongrel'
require File.dirname(__FILE__) + '/testhelp.rb'


class TestCommand < GemPlugin::Plugin "/commands"
  include Mongrel::Command::Base

  def configure
    options [
      ["-e", "--environment ENV", "Rails environment to run as", :@environment, ENV['RAILS_ENV'] || "development"],
      ['', '--user USER', "User to run as", :@user, nil],
      ["-d", "--daemonize", "Whether to run in the background or not", :@daemon, false],
      ["-x", "--test", "Used to let the test run failures", :@test, false],
    ]
  end

  def validate
    valid_dir? ".", "Can't validate current directory."
    valid_exists? "Rakefile", "Rakefile not there, test is invalid."
    if @test
      valid_exist? "BADFILE", "Yeah, badfile"
      valid_file? "BADFILE", "Not even a file"
      valid_dir? "BADDIR", "No dir here"
      valid? false, "Total failure"
    end

    return @valid
  end


  def run
    $test_command_ran = true
  end
end

class CommandTest < Test::Unit::TestCase

  def setup
    $test_command_ran = false
  end

  def teardown
  end

  def run_cmd(args)
    Mongrel::Command::Registry.instance.run args
  end

  def test_run_command
    redirect_test_io do
      run_cmd ["testcommand"]
      assert $test_command_ran, "command didn't run"
    end
  end

  def test_command_error
    redirect_test_io do
      run_cmd ["crapcommand"]
    end
  end

  def test_command_listing
    redirect_test_io do
      run_cmd ["help"]
    end
  end

  def test_options
    redirect_test_io do
      run_cmd ["testcommand","-h"]
      run_cmd ["testcommand","--help"]
      run_cmd ["testcommand","-e","test","-d","--user"]
    end
  end

  def test_version
    redirect_test_io do
      run_cmd ["testcommand", "--version"]
    end
  end

end
