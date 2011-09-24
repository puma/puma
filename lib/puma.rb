
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
require 'puma/configurator'
require 'puma/const'
require 'puma/server'
require 'puma/utils'

Puma::Gems.optional "puma_experimental",
                    ">=#{Puma::Const::PUMA_VERSION}"
