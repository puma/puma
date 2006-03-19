require "irb"
begin
  require "irb/completion"
rescue
  STDERR.puts "Problem lading irb/completion: #$!"
end
require 'rubygems'
require 'yaml'
require 'mongrel'
require 'config/environment'
require 'dispatcher'
require 'mongrel/rails'

$mongrel = {:host => "0.0.0.0", :port => 3000, :mime => nil, :server => nil, :docroot => "public", :tracing => false}


# Tweak the rails handler to allow for tracing
class RailsHandler
  alias :real_process :process

  def process(request, response)
    if $mongrel[:tracing]
      open("log/mongrel.log", "a+") do |f| 
        f.puts ">>>> REQUEST #{Time.now}"
        f.write(request.params.to_yaml)
        f.puts ""
      end
    end

    real_process(request, response)
    
    if $mongrel[:tracing]
      open("log/mongrel.log", "a+") do |f| 
        response.reset
        f.puts ">>>> RESPONSE status=#{response.status} #{Time.now}"
        f.write(response.header.out.read)
        f.puts ""
      end
    end
  end
end

def load_mime_map(mime_map)
  mime = {}
  
  # configure any requested mime map
  if mime_map
    puts "Loading additional MIME types from #{mime_map}"
    mime.merge!(YAML.load_file(mime_map))
    
    # check all the mime types to make sure they are the right format
    mime.each {|k,v| puts "WARNING: MIME type #{k} must start with '.'" if k.index(".") != 0 }
  end
  
  return mime
end

# define a bunch of mongrel goodies
def self.start(options={})
  if $mongrel[:server]
    STDERR.puts "Mongrel already running on #{$mongrel[:host]}:#{$mongrel[:port]}"
  else
    $mongrel.merge! options

    # need this later for safe reloading
    $orig_dollar_quote = $".clone
    
    # configure the rails handler
    rails = RailsHandler.new($mongrel[:docroot], load_mime_map($mongrel[:mime]))
    
    server = Mongrel::HttpServer.new($mongrel[:host], $mongrel[:port])
    server.register("/", rails)
    $mongrel[:rails] = rails
    
    # start mongrel processing thread
    server.run
    STDERR.puts "Mongrel running in #{ENV['RAILS_ENV']} mode on #{$mongrel[:host]}:#{$mongrel[:port]}."
    $mongrel[:server] = server

    nil
  end
end


def self.stop
  if $mongrel[:server]
    $mongrel[:server].stop 
    $mongrel[:server] = nil
    $mongrel[:rails] = nil
  else
    STDERR.puts "Mongrel not running."
  end
  nil
end

def self.restart
  stop
  start
  nil
end

def self.reload
  if $mongrel[:rails]
    STDERR.puts "Reloading rails..."
    $mongrel[:rails].reload!
    STDERR.puts "Done reloading rails."
  else
    STDERR.puts "Mongrel not running."
  end

  nil
end

def self.status
  if $mongrel[:server]
    STDERR.puts "Mongrel running with:"
    $mongrel.each do |k,v|
      STDERR.puts "* #{k}: \t#{v}"
    end
  else
    STDERR.puts "Mongrel not running."
  end

  nil
end

def self.trace
  $mongrel[:tracing] = !$mongrel[:tracing]
  if $mongrel[:tracing]
    STDERR.puts "Tracing mongrel requests and responses to log/mongrel.log"
  else
    STDERR.puts "Tracing is OFF."
  end
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


GemPlugin::Manager.instance.load "mongrel" => GemPlugin::INCLUDE, "rails" => GemPlugin::EXCLUDE

ENV['RAILS_ENV'] ||= 'development'
puts "Loading #{ENV['RAILS_ENV']} environment."

# hook up any rails specific plugins
GemPlugin::Manager.instance.load "mongrel" => GemPlugin::INCLUDE

puts "Starting console.  Mongrel Commands:  start, stop, reload, restart, status, trace, tail"

IRB.start(__FILE__)

