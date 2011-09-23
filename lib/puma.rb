
# Standard libraries
require 'socket'
require 'tempfile'
require 'yaml'
require 'time'
require 'etc'
require 'uri'
require 'stringio'

# Compiled Puma extension
# support multiple ruby version (fat binaries under windows)
begin
  RUBY_VERSION =~ /(\d+.\d+)/
  require "#{$1}/http11"
rescue LoadError
  require 'http11'
end

# Gem conditional loader
require 'puma/gems'
require 'thread'

# Ruby Puma
require 'puma/command'
require 'puma/tcphack'
require 'puma/configurator'
require 'puma/uri_classifier'
require 'puma/const'
require 'puma/http_request'
require 'puma/header_out'
require 'puma/http_response'
require 'puma/server'

# Puma module containing all of the classes (include C extensions)
# for running a Puma web server.  It contains a minimalist HTTP server
# with just enough functionality to service web application requests
# fast as possible.
module Puma

  # Thrown at a thread when it is timed out.
  class TimeoutError < RuntimeError; end

  class BodyReadError < RuntimeError; end
end

Puma::Gems.require "puma_experimental",
                      ">=#{Puma::Const::PUMA_VERSION}"
