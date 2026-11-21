# frozen_string_literal: true

# Standard libraries
require 'socket'
require 'tempfile'
require 'uri'
require 'stringio'

require 'thread'

# use require, see https://github.com/puma/puma/pull/2381
begin
  require 'puma/puma_http11'
rescue LoadError => e
  # Puma can run without the extension, but a broken build ends up here too,
  # e.g. one compiled for another Ruby or missing its OpenSSL library.
  warn "WARNING: Puma could not load its C extension (#{e.message}). " \
    "It will use the slower pure Ruby HTTP parser, and SSL and the child " \
    "subreaper used by mold_worker are unavailable."
end

require_relative 'puma/detect'
require_relative 'puma/json_serialization'

module Puma
  # Loaded on first use, so it reads and checks its PUMA_*_MAX_LENGTH
  # settings only when Puma parses with it.
  autoload :RubyHttpParser, "#{__dir__}/puma/ruby_http_parser"

  # The extension's parser stays reachable under this name, so it can be
  # compared against Puma::RubyHttpParser in the same process.
  NativeHttpParser = HttpParser if const_defined?(:HttpParser, false)

  if !ENV.fetch('PUMA_PURE_RUBY_PARSER', '').empty? || !const_defined?(:HttpParser, false)
    remove_const(:HttpParser) if const_defined?(:HttpParser, false)
    HttpParser = RubyHttpParser
  end

  # Defined by the extension; without it, Puma cannot become a child subreaper.
  unless respond_to?(:enable_child_subreaper)
    def self.enable_child_subreaper
      false
    end
  end

  # when Puma is loaded via `Puma::CLI`, all files are loaded via
  # `require_relative`.  The below are for non-standard loading
  autoload :Const,     "#{__dir__}/puma/const"
  autoload :Server,    "#{__dir__}/puma/server"
  autoload :Launcher,  "#{__dir__}/puma/launcher"
  autoload :LogWriter, "#{__dir__}/puma/log_writer"

  # at present, MiniSSL::Engine is only defined in extension code (puma_http11),
  # not in minissl.rb
  HAS_SSL = const_defined?(:MiniSSL, false) && MiniSSL.const_defined?(:Engine, false)

  HAS_UNIX_SOCKET = Object.const_defined?(:UNIXSocket) && !IS_WINDOWS

  if HAS_SSL
    require_relative 'puma/minissl'
  else
    module MiniSSL
      # this class is defined so that it exists when Puma is compiled
      # without ssl support, as Server and Reactor use it in rescue statements.
      class SSLError < StandardError ; end
    end
  end

  def self.ssl?
    HAS_SSL
  end

  def self.abstract_unix_socket?
    @abstract_unix ||=
      if HAS_UNIX_SOCKET
        begin
          ::UNIXServer.new("\0puma.temp.unix").close
          true
        rescue ArgumentError  # darwin
          false
        end
      else
        false
      end
  end

  # @!attribute [rw] stats_object=
  def self.stats_object=(val)
    @get_stats = val
  end

  # @!attribute [rw] stats_object
  def self.stats
    Puma::JSONSerialization.generate @get_stats.stats
  end

  # @!attribute [r] stats_hash
  # @version 5.0.0
  def self.stats_hash
    @get_stats.stats
  end

  def self.set_thread_name(name)
    Thread.current.name = "puma #{name}"
  end

  # Shows deprecated warning for renamed methods.
  # @example
  #   Puma.deprecate_method_change :on_booted, __callee__, __method__
  #
  def self.deprecate_method_change(method_old, method_caller, method_new)
    if method_old == method_caller
      warn "Use '#{method_new}', '#{method_caller}' is deprecated and will be removed in Puma v9"
    end
  end
end
