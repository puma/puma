
# Standard libraries
require 'socket'
require 'tempfile'
require 'yaml'
require 'time'
require 'etc'
require 'uri'
require 'stringio'

# Compiled Mongrel extension
# support multiple ruby version (fat binaries under windows)
begin
  RUBY_VERSION =~ /(\d+.\d+)/
  require "#{$1}/http11"
rescue LoadError
  require 'http11'
end

# Gem conditional loader
require 'mongrel/gems'
require 'thread'

# Ruby Mongrel
require 'mongrel/handlers'
require 'mongrel/command'
require 'mongrel/tcphack'
require 'mongrel/configurator'
require 'mongrel/uri_classifier'
require 'mongrel/const'
require 'mongrel/http_request'
require 'mongrel/header_out'
require 'mongrel/http_response'
require 'mongrel/server'

# Mongrel module containing all of the classes (include C extensions)
# for running a Mongrel web server.  It contains a minimalist HTTP server
# with just enough functionality to service web application requests
# fast as possible.
module Mongrel

  # Thrown at a thread when it is timed out.
  class TimeoutError < RuntimeError; end

  class BodyReadError < RuntimeError; end
end

Mongrel::Gems.require "mongrel_experimental",
                      ">=#{Mongrel::Const::MONGREL_VERSION}"
