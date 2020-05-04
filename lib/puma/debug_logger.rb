# frozen_string_literal: true

module Puma
  # The implementation of a logging in debug mode.
  #
  class DebugLogger
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
    # - +print_title+ (default true) to log time and error object inspection
    #   on the first line.
    # - +custom_message+ (default nil) custom string to print after title
    #   and before all remaining info.
    #
    def error_dump(error, env=nil, options={})
      return unless @debug || options[:force]

      options[:print_title] = true unless options.key?(:print_title)

      #
      # TODO: add all info we have about request
      #
      string_block = []

      if options[:print_title]
        string_block << "#{Time.now}: #{error.inspect}"
      end

      if options[:custom_message]
        string_block << "#{options[:custom_message]}"
      end

      if env
        string_block << "Handling request { #{env['REQUEST_METHOD']} #{env['PATH_INFO']} }"
      end

      string_block << error.backtrace

      ioerr.puts string_block.join("\n")
    end
  end
end
