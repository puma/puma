require "irb"
begin
  require "irb/completion"
rescue
  STDERR.puts "Problem lading irb/completion: #$!"
end
require 'rubygems'
require 'yaml'
require 'mongrel/rails'
require 'config/environment'
require 'dispatcher'
require 'mongrel/debug'

$mongrel = RailsConfigurator.new :host => "localhost", :port => 3000, :environment => "development", :docroot => "public"

def self.mongrel
  return $mongrel
end

def tail(file="log/#{ENV['RAILS_ENV']}.log")
  STDERR.puts "Tailing #{file}.  CTRL-C to stop it."

  cursor = File.size(file)
  last_checked = Time.now
  tail_thread = Thread.new do
    File.open(file, 'r') do |f|
      loop do
        if f.mtime > last_checked
          f.seek cursor
          last_checked = f.mtime
          contents = f.read
          cursor += contents.length
          print contents
        end
        sleep 1
      end
    end
  end

  trap("INT") { tail_thread.kill }
  tail_thread.join
  nil
end

puts "Starting console.  Mongrel Commands:  start, stop, reload, restart, status, trace, tail"

IRB.start(__FILE__)

