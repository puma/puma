require 'rubygems'
require 'gem_plugin'
require 'mongrel'


class Console < GemPlugin::Plugin "/commands"
  include Mongrel::Command::Base

  def configure 
    options [
             ['-c', '--chdir DIR', "Change to directory before running", :@dir, "."]
            ]
  end

  def validate
    valid_dir? @dir, "Directory is not valid"
    return @valid
  end

  def run
    begin
      Dir.chdir @dir
      load File.join(File.dirname(__FILE__), "console.rb")
    rescue Object
      STDERR.puts "Cannot run the console script: #$!"
    end
  end
end

