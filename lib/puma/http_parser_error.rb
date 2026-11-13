# frozen_string_literal: true

module Puma
  # Raised for a request that is not valid HTTP. It is defined here, as well
  # as in the puma_http11 extension, so that a parser set with the
  # `http_parser` option can raise it when the extension is not loaded.
  class HttpParserError < StandardError; end
end
