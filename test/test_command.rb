# Copyright (c) 2011 Evan Phoenix
# Copyright (c) 2005 Zed A. Shaw 

require 'test/testhelp'

class TestCommand < GemPlugin::Plugin "/commands"
  include Puma::Command::Base

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
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def teardown
  end

  def run_cmd(args)
    Puma::Command::Registry.new(@stdout, @stderr).run args
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
