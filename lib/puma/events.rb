require 'puma/const'
require 'stringio'

module Puma
  class Events

    include Const

    def initialize(stdout, stderr)
      @stdout = stdout
      @stderr = stderr
    end

    attr_reader :stdout, :stderr

    def parse_error(server, env, error)
      @stderr.puts "#{Time.now}: HTTP parse error, malformed request (#{env[HTTP_X_FORWARDED_FOR] || env[REMOTE_ADDR]}): #{error.inspect}"
      @stderr.puts "#{Time.now}: ENV: #{env.inspect}\n---\n"
    end

    def unknown_error(server, env, error, kind="Unknown")
      if error.respond_to? :render
        error.render "#{Time.now}: #{kind} error", @stderr
      else
        @stderr.puts "#{Time.now}: #{kind} error: #{error.inspect}"
        @stderr.puts error.backtrace.join("\n")
      end
    end

    DEFAULT = new(STDOUT, STDERR)

    def self.strings
      Events.new StringIO.new, StringIO.new
    end
  end
end
