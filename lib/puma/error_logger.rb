# frozen_string_literal: true

require 'puma/const'

module Puma
  # The implementation of a logging in debug mode.
  #
  class ErrorLogger
    include Const

    attr_reader :ioerr

    REQUEST_FORMAT = %{"%s %s%s" - (%s)}

    def initialize(ioerr)
      @ioerr = ioerr
      @ioerr.sync = true

      @debug = ENV.key? 'PUMA_DEBUG'
    end

    def self.stdio
      new $stderr
    end

    # Print occured error details.
    # +options+ hash with additional options:
    # - +error+ is an exception object
    # - +req+ the http request
    # - +text+ (default nil) custom string to print in title
    #   and before all remaining info.
    #
    def info(options={})
      error_dump(options)
    end

    # Print occured error details only if
    # environment variable PUMA_DEBUG is defined.
    # +options+ hash with additional options:
    # - +error+ is an exception object
    # - +req+ the http request
    # - +text+ (default nil) custom string to print in title
    #   and before all remaining info.
    #
    def debug(options={})
      return unless @debug
      error_dump(options)
    end

    private

    def error_dump(options={})
      error = options[:error]
      req = options[:req]
      env = req.env if req
      text = options[:text]

      string_block = []
      formatted_text = " #{text}" if text
      formatted_error = ": #{error.inspect}" if error
      string_block << "#{Time.now}#{formatted_text}#{formatted_error}"

      if env
        string_block << "Handling request { #{request_title(env)} }"
        string_block << "Headers: #{request_headers(env)}"
        string_block << "Body: #{req.body}"
      end

      string_block << error.backtrace if error

      ioerr.puts string_block.join("\n")
    end

    def request_title(env)
      REQUEST_FORMAT % [
        env[REQUEST_METHOD],
        env[REQUEST_PATH] || env[PATH_INFO],
        env[QUERY_STRING] || "",
        env[HTTP_X_FORWARDED_FOR] || env[REMOTE_ADDR] || "-"
      ]
    end

    def request_headers(env)
      headers = env.select { |key, _| key.start_with?('HTTP_') }
      headers.map { |key, value| [key[5..-1], value] }.to_h.inspect
    end
  end
end
