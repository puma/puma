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
require 'net/http'

class MongrelConsoleRunner

  def initialize
    @port = 3000
    @env = "development"
  end

  def tail(file="log/#{@env}.log")
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

  def start(port=@port, env=@env)
    `mongrel_rails start #{port} #{env} -d`
  end

  def stop
    `mongrel_rails stop`
  end

  def restart(port=@port, env=@env)
    stop
    start(port, env)
  end

  def status
    if File.exist? "log/mongrel.pid"
      pid = open("log/mongrel.pid") {|f| f.read.to_i }
      puts "Running on port #@port in env #@env with PID #{pid}"
    else
      puts "Mongrel not running."
    end
  end

  def get(url="/")
    Net::HTTP.get("localhost", url, @port)
  end
end


$mongrel = MongrelConsoleRunner.new
puts "Starting console.  mongrel.[start | stop | restart | status | tail | get]"
$mongrel.status

def self.mongrel
  $mongrel
end

IRB.start(__FILE__)
