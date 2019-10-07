# frozen_string_literal: true

require 'uri'
require 'socket'
require 'forwardable'

require 'puma/const'
require 'puma/util'
require 'puma/binding'
require 'puma/minissl/context_builder'
require 'puma/binding/tcp_binding'
require 'puma/binding/unix_binding'
require 'puma/binding/ssl_binding'

module Puma
  class Binder
    include Puma::Const

    def initialize(events)
      @events = events
      @bindings = []
    end

    attr_reader :bindings

    def close
      @bindings.each(&:close)
    end

    def bound_servers
      @bindings.map(&:server)
    end

    def env_for_server(server)
      @env_cache ||= Hash.new do |h, key|
        binding_env = @bindings.find { |b| b.server == key }.env
        env = Const::PROTO_ENV.dup
        env.merge!(binding_env)["rack.errors".freeze] = @events.stderr
        h[key] = env
      end
      @env_cache[server]
    end

    def parse(binds, logger)
      binds.each do |str|
        uri = URI.parse str
        case uri.scheme
        when "tcp"
          if uri.host == "localhost"
            loopback_addresses.each do |loopback|
              uri.host = loopback
              @bindings << TCPBinding.new(uri)
            end
          else
            @bindings << TCPBinding.new(uri)
          end
        when "unix"
          @bindings << UnixBinding.new(uri)
        when "ssl"
          if uri.host == "localhost"
            loopback_addresses.each do |loopback|
              uri.host = loopback
              @bindings << SSLBinding.new(uri)
            end
          else
            @bindings << SSLBinding.new(uri)
          end
        else
          logger.error "Invalid URI: #{str}"
        end
      end

      @bindings.each { |b| logger.log "* Listening on #{b}" }
    end

    def loopback_addresses
      ipv4 = Socket.ip_address_list.select {|i| i.ipv4_loopback? }.map(&:ip_address)
      ipv6 = Socket.ip_address_list.select {|i| i.ipv6_loopback? }.map { |i| "[#{i.ip_address}]" }
      ipv4 + ipv6
    end

    attr_reader :connected_port

    def close_listeners
      @bindings.each do |binder|
        binder.close
        binder.unlink_fd if binder.unix?
      end
    end

    def close_unix_paths
      @bindings.select { |b| UnixBinding === b }.each(&:unlink_fd)
    end

    def redirects_for_restart
      redirects = {:close_others => true}
      @bindings.each_with_index do |binder, i|
        server_integer = binder.server.to_i
        ENV["PUMA_INHERIT_#{i}"] = "#{server_integer}:#{binder}"
        redirects[server_integer] = server_integer
      end
      redirects
    end
  end
end
