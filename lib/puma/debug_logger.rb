# frozen_string_literal: true

require 'puma/const'

module Puma
  # The implementation of a logging in debug mode.
  #
  class DebugLogger
    include Const

    attr_reader :ioerr

    def initialize(ioerr)
      @ioerr = ioerr
      @ioerr.sync = true

      @debug = ENV.key? 'PUMA_DEBUG'
    end

    def self.stdio
      new $stderr
    end

    # Any error has occured during debug mode.
    # +error+ is an exception object, +env+ the request,
    # +options+ hash with additional options:
    # - +force+ (default nil) to log info even if debug mode is turned off
    # - +custom_message+ (default nil) custom string to print after title
    #   and before all remaining info.
    #
    def error_dump(error, env=nil, options={})
      return unless @debug || options[:force]

      #
      # TODO: add all info we have about request
      #
      string_block = []

      custom_message = " #{options[:custom_message]}:" if options[:custom_message]
      string_block << "#{Time.now}#{custom_message} #{error.inspect}"

      if env
        string_block << "Handling request { #{env[REQUEST_METHOD]} #{env[REQUEST_PATH] || env[PATH_INFO]} } (#{env[HTTP_X_FORWARDED_FOR] || env[REMOTE_ADDR]})"
      end

      string_block << error.backtrace

      ioerr.puts string_block.join("\n")
    end
  end
end
