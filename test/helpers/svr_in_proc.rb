# frozen_string_literal: true

require_relative 'tmp_path'
require_relative 'svr_base'
require_relative 'sockets'

require "puma/configuration"
require "puma/events"
# avoids circular require when running single tests
require 'nio'

module TestPuma
  class SvrInProc < SvrBase
    include TmpPath
    include TestPuma::Sockets

    def teardown
      return if skipped?
      if @server
        @server.stop true
        @server.binder.close_listeners
      end

      if @ios_to_close
        @ios_to_close.each do |io|
          io.close if io.is_a?(IO) && !io.closed?
          io = nil
        end
      end

      if defined?(@bind_port) && @bind_port
        # ssl sockets need extra time to close?
        sleep 2.0 if @bind_type == :ssl
        begin
          TCPServer.new(HOST, @bind_port).close
        rescue SystemCallError => e
          flunk "Bind socket should be closed (#{e.class} #{@bind_port})"
        end
      end

      if defined?(@bind_path) && @bind_path
        refute File.exist?(@bind_path), 'Bind path should be removed'
        File.unlink(@bind_path) rescue nil
      end
    end

    def bind_type(type = :tcp, config: nil, config_path: nil, ssl_opts: nil)
      unless BIND_TYPES.include? type
        raise ArgumentError, "Invalid argument #{type.inspect}"
      end
      @bind_type = type unless type == :none
      @config = config
      @ssl_opts = ssl_opts
    end

    def start_server(app = nil, options = {})
      bind_type :tcp unless @bind_type

      options[:binds] ||= []
      if (t = options.delete :threads) && t =~ /\A\d+:\d+\z/
        min, max = t.split(':').map(&:to_i)
        options[:min_threads] = min
        options[:max_threads] = max
      end

      case @bind_type
      when :ssl
        @bind_port = UniquePort.call
        @bind_ssl = Puma::DSL.ssl_bind_str HOST, @bind_port,
          ssl_default_opts.merge(@ssl_opts)
        options[:binds] << @bind_ssl
      when :tcp
        @bind_port = UniquePort.call
        options[:binds] << "tcp://#{HOST}:#{@bind_port}"
      when :aunix
        require 'securerandom'
        @bind_path = "@#{SecureRandom.uuid}"
        options[:binds] << "unix://#{@bind_path}"
      when :unix
        @bind_path = tmp_path '.bind'
        options[:binds] << "unix://#{@bind_path}"
      end

      @events = Puma::Events.strings

      @conf = if @config
        Puma::Configuration.new(options) { |user_dsl, file_dsl, default_dsl|
          file_dsl.send(:instance_eval, @config)
        }.tap(&:clamp)
      else
        Puma::Configuration.new(options).tap(&:clamp)
      end

      @server = Puma::Server.new app, @events, @conf.options
      @server.inherit_binder Puma::Binder.new(@events, @conf)
      @server.binder.parse @conf.options[:binds], @events
      @server.run
      sleep 0.01
    end

    def rack_env_to_body
      lambda { |env|
        body = ''.dup
        env.sort.each { |a| body << "#{a.first}: #{a[1]}\n" }
        [200, {}, [body]]
      }
    end

    def ci_test
      require 'securerandom'

      # ~10k response is default

      env_len = ENV['CI_TEST_KB'] ? ENV['CI_TEST_KB'].to_i : nil

      long_header_hash = {}

      25.times { |i| long_header_hash["X-My-Header-#{i}"] = SecureRandom.hex(25) }

      lambda { |env|
        resp = "#{Process.pid}\nHello World\n".dup

        if (dly = env['HTTP_DLY'])
          sleep dly.to_f
          resp << "Slept #{dly}\n"
        end

        # length = 1018  bytesize = 1024
        str_1kb = "──#{SecureRandom.hex 507}─\n"

        len = (env['HTTP_LEN'] || env_len || 10).to_i
        resp << (str_1kb * len)
        long_header_hash['Content-Type'] = 'text/plain; charset=UTF-8'
        long_header_hash['Content-Length'] = resp.bytesize.to_s
        [200, long_header_hash.dup, [resp]]
      }
    end

  end
end
