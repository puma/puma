# frozen_string_literal: true

# svr_base loads helper.rb, which loads Puma correctly.  Hence, must be before
# puma/control_cli require

require_relative 'tmp_path'
require_relative 'svr_base'
require 'puma/control_cli'
require_relative 'sockets'

module TestPuma

  # The class is a superclass for all test files that need to create a Puma
  # instance running in a subprocess.  It uses `IO.popen`.
  #
  # The `#teardown` method handles closing test client sockets and closing the
  # Puma instance.
  #
  # @note Windows signal implementation is poor, so any tests running on Windows
  # need to define a `ctrl_type`.  This allows the server to be shutdown
  # via `Puma::ControlCLI`.  Otherwise it is shutdown with a signal.
  #
  class SvrPOpen < SvrBase
    include TmpPath
    include TestPuma::Sockets

    BASE = defined?(Bundler) ? "bundle exec #{Gem.ruby} -Ilib" :
      "#{Gem.ruby} -Ilib"

    CTRL_TYPES = %i[pid pid_file ssl state_pid state_tcp state_aunix state_unix tcp aunix unix]

    attr_accessor :stopped

    # Initializes variables, performs no actions.
    def setup
      super

      @ctrl_type = nil
      @ctrl_config = nil
      @ctrl_path  = nil
      @ctrl_port  = nil
      @pid_path   = nil
      @state_path = nil

      @config_path_is_tmp = nil

      @puma_threads = nil
      @puma_workers = nil
      @pid = nil
      @server_stopped = nil
    end

    # Stops server, closes all members of `@ios_to_close`, verifies that listeners'
    # ports and/or files are closed.
    def teardown
      return if skipped?
      if @server && @pid &&
        stop_puma
      end

      if @ios_to_close
        ssl = ::TestPuma.const_defined?(:SktSSL) ? ::TestPuma::SktSSL : nil
        @ios_to_close.each do |io|
          next if io.nil?
          begin
            if io.to_io.is_a?(IO) && !io.closed?
              if ssl && io.is_a?(ssl)
                io.sysclose
              else
                io.close
              end
            end
          rescue Errno::EBADF
          end
          io = nil
        end
      end

      if defined?(@server) && @server
        begin
          Process.wait2 @server.pid # , Process::WNOHANG
        rescue Errno::ECHILD
        end
        @server.close unless @server.closed?
        @server = nil
      end

      bind_err = nil ; ctrl_err = nil

      if defined?(@bind_port) && @bind_port
        # ssl sockets need extra time to close?
        sleep_retry = true
        begin
          TCPServer.new(HOST, @bind_port).close
        rescue SystemCallError => e
          if sleep_retry
            sleep_retry = false
            sleep 2
            retry
          end
          bind_err = "#{e.class} #{@bind_port}"
        end
      end

      if defined?(@ctrl_port) && @ctrl_port
        sleep 1.0 if @ctrl_type == :ssl
        begin
          TCPServer.new(HOST, @ctrl_port).close
        rescue SystemCallError => e
          ctrl_err = "#{e.class} #{@ctrl_port}"
        end
      end

      if bind_err && ctrl_err
        flunk "Bind and Control sockets should be closed (#{bind_err}, #{ctrl_err})"
      elsif bind_err
        flunk "Bind socket should be closed (#{bind_err})"
      elsif ctrl_err
        flunk "Control socket should be closed (#{ctrl_err})"
      end

      if @config_path_is_tmp && defined?(@config_path) && @config_path
        File.unlink(@config_path) rescue nil
      end

      if defined?(@bind_path) && @bind_path
        sleep 0.3 if File.exist? @bind_path
        refute File.exist?(@bind_path), 'Bind path should be removed'
        File.unlink(@bind_path) rescue nil
      end

      if defined?(@ctrl_path) && @ctrl_path
        sleep 0.3 if File.exist? @ctrl_path
        refute File.exist?(@ctrl_path), 'Control path should be removed'
        File.unlink(@ctrl_path) rescue nil
      end
    end

    # Configures the server.
    # @param [Symbol] The type the type of listener socket.  Allowable values are
    #   :ssl, :tcp, :aunix, and :unix.
    # @param [String] config: a configuration string that is evaluated
    # @param [String] config_file: path to a config file
    # @param [Hash] ssl_opts: path to a config file
    # @note `config:` and `config_path:` parameters are mutually exclusive
    #
    def setup_puma(type = :tcp, config: nil, config_path: nil, ssl_opts: {})
      if config && config_path
        raise ArgumentError, "config: and config_path: cannot both be used"
      end

      unless BIND_TYPES.include? type
        raise ArgumentError, "Invalid argument #{type.inspect}"
      end

      @config_path = nil
      unless @bind_type
        case type
        when :aunix
          @bind_path = "@#{SecureRandom.uuid}"
        when :ssl
          @bind_port = UniquePort.call
          @bind_ssl = ::Puma::DSL.ssl_bind_str HOST, @bind_port,
            ssl_default_opts.merge(ssl_opts)
        when :tcp
          @bind_port = UniquePort.call
        when :unix
          @bind_path = tmp_path '.bind'
        end
        @bind_type = type
      end

      if config
        unless config.is_a? ::String
          config = config.call
        end
        @config_path = tmp_path '.config', contents: config.strip
        @config_path_is_tmp = true
      end
      if config_path
        @config_path = config_path
      end
    end

    # Configures the control server, if used.
    # @param [Symbol] type control type to use.  Options are:
    #   * `:pid` use a pid with signals
    #   * `:pid_file` use pid file with signals
    #   * `:ssl` use an ssl socket
    #   * `:tcp` use a tcp socket
    #   * `:unix` or `:aunix` use a unix socket, either file or abstract
    #   * `:state_pid`, `:state_tcp`, `:state_aunix`, `:state_unix` as above,
    #     but obtain info from the state file
    #
    # @param [String] config_path: obtain configuration from the config file
    #
    def ctrl_type(type = nil, config_path: nil)
      unless config_path || CTRL_TYPES.include?(type)
        raise ArgumentError, "Invalid argument #{type.inspect}"
      end
      @ctrl_path  = nil
      @pid_path   = nil
      @state_path = nil
      @ctrl_port  = nil
      @ctrl_type   = type
      @ctrl_config = config_path
    end

    # Send a command to the Server using `ControlCLI`.
    # @param [String] arg the command to send to the Puma Server
    # @param [Boolean] log_cmd: logs the command when set
    #
    def cli_pumactl(arg, log_cmd: false)
      arg = arg.to_s
      args =
        case @ctrl_type
        when nil
          []
        when :pid
          %W[-p #{@pid}]
        when :pid_file
          %W[-P #{@pid_path}]
        when :ssl
          # todo
        when :state_pid, :state_tcp, :state_aunix, :state_unix
          %W[-S #{@state_path}]
        when :tcp
          %W[-C tcp://#{HOST}:#{@ctrl_port} -T #{TOKEN}]
        when :aunix, :unix
          %W[-C unix://#{@ctrl_path} -T #{TOKEN}]
        end

      (args << '-F' << @ctrl_config) if @ctrl_config

      if args.empty?
        if windows?
          raise 'ctrl is not cofigured for Windows!'
        else
          args = %W[-p #{@pid}]
        end
      end

      args << arg if arg
      puts '', args.inspect if log_cmd

      r, w = IO.pipe

      Puma::ControlCLI.new(args, w, w).run

      @ios_to_close << r
      @stopped = ['halt', 'stop', 'stop-sigterm'].include? arg
      w.close
      r
    end

    # Starts Puma using `IO.popen`.
    # @param [String] argv command line string
    # @param [Hash] env: hash used for `IO.popen`'s env
    # @param [Boolean] log: write server output to console, normally just used to debug
    # @param [Boolean] log_cmd: writes `IO.popen`'s cmd string to the console,
    #    normally just used to debug
    # @param [Boolean] wait_for_boot: Waits until server is booted by reading
    #   the server console output.  Setting to false allows `@server` to be read.
    # @return [IO] the io returned by `IO.popen`.
    def start_puma(argv = nil, env: nil, log: false, log_cmd: false, wait_for_boot: true)
      @pids_stopped = []
      @pids_waited  = []
      setup_puma unless @bind_type # defaults to tcp

      puma_bin = File.expand_path '../../bin/puma', __dir__
      cmd = "#{BASE} #{puma_bin}".dup

      cmd << " -C #{@config_path}" if @config_path

      case @bind_type
      when :ssl
        # windows needs quotes
        cmd << " -b \"#{@bind_ssl}\""
      when :tcp
        cmd << " -b tcp://#{HOST}:#{@bind_port}"
      when :aunix, :unix
        cmd << " -b unix://#{@bind_path}"
      end

      cmd << " -w #{@puma_workers}" if @puma_workers
      cmd << " -t #{@puma_threads}" if @puma_threads
      cmd << ctrl_setup
      cmd << " #{argv}" if argv
      puts('', cmd.inspect) if log_cmd

      if env
        @server = IO.popen env, cmd, 'r', :err=>[:child, :out]
      else
        @server = IO.popen cmd, 'r', :err=>[:child, :out]
      end

      @pid ||= @server.pid
      wait_for_puma_to_boot(log: log) if wait_for_boot
      @server_stopped = nil
      @server
    end

    # Sets or reads the number of threads, acts as both a setter and a getter.
    # Returns the number of threads when called without a parameter.
    # @param [String, nil] The number of threads.
    # @return [Integer, nil]
    def puma_threads(qty = 'no')
      if qty == 'no'
        @puma_threads
      elsif qty.nil? || qty.is_a?(String)
        @puma_threads = qty
      else
        raise ArgumentError, 'Parameter (#{qty.inspect}) should be an Integer or nil'
      end
    end

    # Sets or reads the number of workers, acts as both a setter and a getter.
    # Returns the number of workers when called without a parameter.
    # @param [Integer, nil] The number of workers.
    # @return [Integer, nil]
    def puma_workers(qty = 'no')
      if qty == 'no'
        @puma_workers
      elsif qty.nil? || qty.is_a?(Integer)
        @puma_workers = qty
      else
        raise ArgumentError, 'Parameter (#{qty.inspect}) should be an Integer or nil'
      end
    end

    # Stops the server. Uses `Puma::ControlCLI` if it is configured, otherwise it signals.
    # Rescue statements are just in case method is called with a server that is
    # already stopped/killed, especially since Process.wait2 is blocking.
    # @param [Int] pid the server pid
    # @param [Symbol] signal: stop signal to use
    # @param [Boolean] wait: whether `Process.wait2` is called
    # @param [Boolean] log: writes server output to console, normally just used to debug
    # @param [Boolean] log_cmd: writes `Puma::ControlCLI`'s arg string to the console,
    #    normally just used to debug
    # @param [Boolean] wait_for_stop: Waits until server is stopped by reading
    #   the server console output.  Setting to false allows `@server` to be read.
    def stop_puma(pid = @pid, signal: nil, wait: true, log: false, log_cmd: false, wait_for_stop: true)
      return if self.stopped
      ret = []
      if @pid_path && File.exist?(@pid_path)
        pid = File.read(@pid_path).strip.to_i
      end

      unless @pids_stopped.include?(pid)
        # needed to switch to signal if cli_control isn't set up
        if signal.nil? && @ctrl_type.nil? && @ctrl_config.nil?
          signal = :INT
        end
        if signal
          begin
            Process.kill signal, pid
          rescue Errno::ESRCH
          end
        else
          cli_pumactl 'stop', log_cmd: log_cmd
        end
        assert_server_gets(cmd_to_log_str('stop'), log: log) if wait_for_stop
        @pids_stopped << pid
      end

      if wait && !@pids_waited.include?(pid)
        @pids_waited << pid
        begin
          ret = Process.wait2 pid
        rescue Errno::ECHILD
        end
      end
      self.stopped = true
      @server = nil
      ret
    end

    # Waits for server to boot.  Reads `IO.popen` output.
    # @param [Boolean] log: logs output for debug
    def wait_for_puma_to_boot(log: false)
      puts('', "──── #{full_name} ────  Waiting for server to boot") if log
      until (l = @server.gets.to_s).include? 'Use Ctrl-C to stop'
        if (pid = l[/ PID: +(\d+)$/i, 1])
          @pid = pid.to_i
        end
        puts l if log && !l.empty?
        sleep 0.005
      end
      puts(l, '──── Server booted!') if log
    end

    # Gets worker pids from @server output
    # @param [Integer] phase the worker phase to look for
    # @param [Integer] size the number of worker pids to find, defaults to
    #   `@workers`
    # @param [Boolean] log: show the server log in the console
    #
    def get_worker_pids(phase = 0, size = nil, log: false)
      STDOUT.puts '', "──── #{full_name} ────  get_worker_pids" if log
      size ||= @puma_workers
      pids = []
      re = /PID: (\d+)\) booted in \d+\.\d+s, phase: #{phase}/i
      while pids.size < size
        l = @server.gets
        STDOUT.puts l if log
        if (pid = l[re, 1])
          pids << pid.to_i
        end
      end
      pids
    end

    # Gets the server output, and asserts that it matches a String or RegExp.
    # @param [String, Regexp, Array] str_ary a single string or Regexp, or a mixed array of them
    # @param [Boolean] log: show the server log in the console
    #
    def assert_server_gets(str_ary, log: nil)
      if str_ary.is_a? ::Array
        puts('', "──── #{full_name} ────  #{str_ary.inspect}") if log
        until str_ary.empty?
          str = str_ary.shift
          gets_match str, log: log
        end
      else
        puts('', "──── #{full_name} ────  '#{str_ary}'") if log
        gets_match str_ary, log: log
      end
    end

    # Pass a command, returns a String that should appear in the server log
    # @param [String,Symbol] cmd the command
    # @return [String,Array] a String or array of strings that should be output
    #
    def cmd_to_log_str(cmd)
      str = cmd.to_s
      # common log strings
      restarting  = 'Restarting...'
      ctrl_c      = 'Use Ctrl-C to stop'
      worker_boot = " - Worker #{@puma_workers - 1} (PID: " if @puma_workers

      case str
      when 'halt'
        'Stopping immediately!'
      when 'stop', 'stop-sigterm'
        'Goodbye!'
      when 'phased-restart'
        if @puma_workers
          ['Starting phased worker', worker_boot]
        else
          [restarting, ctrl_c]
        end
      when 'restart'
        if @puma_workers
          [restarting, worker_boot]
        else
          [restarting, ctrl_c]
        end
      end
    end

    private

    # Called by `start_puma`, returns the string used to setup the control server in Puma
    # @return [String]
    def ctrl_setup
      ctrl_type_str = @ctrl_type.to_s

      if ctrl_type_str.start_with? 'state'
        @state_path = tmp_path '.state'
      end

      if ctrl_type_str.end_with? 'tcp'
        @ctrl_port = UniquePort.call
      elsif ctrl_type_str.end_with? 'aunix'
        @ctrl_path = "@#{SecureRandom.uuid}"
      elsif ctrl_type_str.end_with? 'unix'
        @ctrl_path = tmp_path '.ctrl'
      end

      case @ctrl_type
      when nil, :pid
        ''
      when :pid_file
        @pid_path = tmp_path '.pid'
        " --pidfile #{@pid_path}"
      when :ssl
        # todo
      when :state_pid
        " --state #{@state_path}"
      when :state_tcp
        " --control-token #{TOKEN} --state #{@state_path} --control-url tcp://#{HOST}:#{@ctrl_port}"
      when :state_aunix, :state_unix
        " --control-token #{TOKEN} --state #{@state_path} --control-url unix://#{@ctrl_path}"
      when :tcp
        " --control-token #{TOKEN} --control-url tcp://#{HOST}:#{@ctrl_port}"
      when :aunix, :unix
        " --control-token #{TOKEN} --control-url unix://#{@ctrl_path}"
      end
    end

    # Asserts whether server's output matches a String or a RegExp.
    # @param [String,RegExp] str
    # @param [Boolean] log: logs the server output to console
    #
    def gets_match(str, log: nil)
      if str.is_a? Regexp
        until (l = @server.gets || '') =~ str
          puts l if log && !l.empty?
          sleep 0.001
        end
      else
        until (l = @server.gets || '').include? str
          puts l if log && !l.empty?
          sleep 0.001
        end
      end
      puts l if log
      if str.is_a? Regexp
        assert_match str, l
      else
        assert_includes l, str
      end
    end
  end
end
