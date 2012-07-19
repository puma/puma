require 'puma/const'
require 'stringio'

module Puma
  # The default implement of an event sink object used by Server
  # for when certain kinds of events occur in the life of the server.
  #
  # The methods available are the events that the Server fires.
  #
  class Events

    include Const

    # Create an Events object that prints to +stdout+ and +stderr+.
    #
    def initialize(stdout, stderr)
      @stdout = stdout
      @stderr = stderr
    end

    attr_reader :stdout, :stderr

    # Write +str+ to +@stdout+
    #
    def log(str)
      @stdout.puts str
    end

    # Write +str+ to +@stderr+
    #
    def error(str)
      @stderr.puts "ERROR: #{str}"
      exit 1
    end

    # An HTTP parse error has occured.
    # +server+ is the Server object, +env+ the request, and +error+ a
    # parsing exception.
    #
    def parse_error(server, env, error)
      @stderr.puts "#{Time.now}: HTTP parse error, malformed request (#{env[HTTP_X_FORWARDED_FOR] || env[REMOTE_ADDR]}): #{error.inspect}"
      @stderr.puts "#{Time.now}: ENV: #{env.inspect}\n---\n"
    end

    # An unknown error has occured.
    # +server+ is the Server object, +env+ the request, +error+ an exception
    # object, and +kind+ some additional info.
    #
    def unknown_error(server, error, kind="Unknown")
      if error.respond_to? :render
        error.render "#{Time.now}: #{kind} error", @stderr
      else
        @stderr.puts "#{Time.now}: #{kind} error: #{error.inspect}"
        @stderr.puts error.backtrace.join("\n")
      end
    end

    DEFAULT = new(STDOUT, STDERR)

    # Returns an Events object which writes it's status to 2 StringIO
    # objects.
    #
    def self.strings
      Events.new StringIO.new, StringIO.new
    end
  end
end
