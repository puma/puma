module Puma
  class Launcher
    def initialize(cli_options = {})
      @cli_options = cli_options
      @runner      = nil
    end

    ## THIS STUFF IS NEEDED FOR RUNNER

    # Delegate +log+ to +@events+
    #
    def log(str)
      @events.log str
    end

    def config
      @config
    end

    def stats
      @runner.stats
    end

    def halt
      @status = :halt
      @runner.halt
    end

    def binder
      @binder
    end

    def events
      @events
    end

    # Delegate +error+ to +@events+
    #
    def error(str)
      @events.error str
    end

    def debug(str)
      @events.log "- #{str}" if @options[:debug]
    end

    def write_state
      write_pid

      path = @options[:state]
      return unless path

      state = { 'pid' => Process.pid }
      cfg = @config.dup

      [
        :logger,
        :before_worker_shutdown, :before_worker_boot, :before_worker_fork,
        :after_worker_boot,
        :on_restart, :lowlevel_error_handler
      ].each { |k| cfg.options.delete(k) }
      state['config'] = cfg

      require 'yaml'
      File.open(path, 'w') { |f| f.write state.to_yaml }
    end

    def delete_pidfile
      path = @options[:pidfile]
      File.unlink(path) if path && File.exist?(path)
    end

    # If configured, write the pid of the current process out
    # to a file.
    #
    def write_pid
      path = @options[:pidfile]
      return unless path

      File.open(path, 'w') { |f| f.puts Process.pid }
      cur = Process.pid
      at_exit do
        delete_pidfile if cur == Process.pid
      end
    end

    attr_accessor :options, :binder, :config, :events, :argv
    ## THIS STUFF IS NEEDED FOR RUNNER


    def setup(options)
      @options = options
      generate_restart_data

      parse_options

      dir = @options[:directory]
      Dir.chdir(dir) if dir

      prune_bundler if prune_bundler?

      set_rack_environment

      if clustered?
        @events.formatter = Events::PidFormatter.new
        @options[:logger] = @events

        @runner = Cluster.new(self)
      else
        @runner = Single.new(self)
      end

      @status = :run
    end


    attr_accessor :runner

    def stop
      @status = :stop
      @runner.stop
    end

    def restart
      @status = :restart
      @runner.restart
    end

    def run
      setup_signals
      set_process_title
      @runner.run

      case @status
      when :halt
        log "* Stopping immediately!"
      when :run, :stop
        graceful_stop
      when :restart
        log "* Restarting..."
        @runner.before_restart
        restart!
      when :exit
        # nothing
      end
    end


    def clustered?
      @options[:workers] > 0
    end

    def jruby?
      Puma.jruby?
    end

    def windows?
      Puma.windows?
    end


    def prune_bundler
      return unless defined?(Bundler)
      puma = Bundler.rubygems.loaded_specs("puma")
      dirs = puma.require_paths.map { |x| File.join(puma.full_gem_path, x) }
      puma_lib_dir = dirs.detect { |x| File.exist? File.join(x, '../bin/puma-wild') }

      unless puma_lib_dir
        log "! Unable to prune Bundler environment, continuing"
        return
      end

      deps = puma.runtime_dependencies.map do |d|
        spec = Bundler.rubygems.loaded_specs(d.name)
        "#{d.name}:#{spec.version.to_s}"
      end

      log '* Pruning Bundler environment'
      home = ENV['GEM_HOME']
      Bundler.with_clean_env do
        ENV['GEM_HOME'] = home
        ENV['PUMA_BUNDLER_PRUNED'] = '1'
        wild = File.expand_path(File.join(puma_lib_dir, "../bin/puma-wild"))
        args = [Gem.ruby, wild, '-I', dirs.join(':'), deps.join(',')] + @original_argv
        Kernel.exec(*args)
      end
    end

    def redirect_io
      @runner.redirect_io
    end

    def phased_restart
      unless @runner.respond_to?(:phased_restart) and @runner.phased_restart
        log "* phased-restart called but not available, restarting normally."
        return restart
      end
      true
    end

    private
    def restart_args
      cmd = @options[:restart_cmd]
      if cmd
        cmd.split(' ') + @original_argv
      else
        @restart_argv
      end
    end
    public


    def jruby_daemon_start
      require 'puma/jruby_restart'
      JRubyRestart.daemon_start(@restart_dir, restart_args)
    end

    def reload_worker_directory
      @launcher.reload_worker_directory
    end

    def restart!
        @options[:on_restart].each do |block|
          block.call self
        end

        if jruby?
          close_binder_listeners

          require 'puma/jruby_restart'
          JRubyRestart.chdir_exec(@restart_dir, restart_args)
        elsif windows?
          close_binder_listeners

          argv = restart_args
          Dir.chdir(@restart_dir)
          argv += [redirects] if RUBY_VERSION >= '1.9'
          Kernel.exec(*argv)
        else
          redirects = {:close_others => true}
          @binder.listeners.each_with_index do |(l, io), i|
            ENV["PUMA_INHERIT_#{i}"] = "#{io.to_i}:#{l}"
            redirects[io.to_i] = io.to_i
          end

          argv = restart_args
          Dir.chdir(@restart_dir)
          argv += [redirects] if RUBY_VERSION >= '1.9'
          Kernel.exec(*argv)
        end
    end


  private
    def unsupported(str)
      @events.error(str)
      raise UnsupportedOption
    end

    def parse_options
      find_config

      @config = Puma::Configuration.new @cli_options

      # Advertise the Configuration
      Puma.cli_config = @config

      @config.load

      @options = @config.options

      if clustered? && (jruby? || windows?)
        unsupported 'worker mode not supported on JRuby or Windows'
      end

      if @options[:daemon] && windows?
        unsupported 'daemon mode not supported on Windows'
      end
    end

    def find_config
      if @cli_options[:config_file] == '-'
        @cli_options[:config_file] = nil
      else
        @cli_options[:config_file] ||= %W(config/puma/#{env}.rb config/puma.rb).find { |f| File.exist?(f) }
      end
    end

    def graceful_stop
      @runner.stop_blocked
      log "=== puma shutdown: #{Time.now} ==="
      log "- Goodbye!"
    end

    def set_process_title
      Process.respond_to?(:setproctitle) ? Process.setproctitle(title) : $0 = title
    end

    def title
      buffer = "puma #{Puma::Const::VERSION} (#{@options[:binds].join(',')})"
      buffer << " [#{@options[:tag]}]" if @options[:tag] && !@options[:tag].empty?
      buffer
    end

    def set_rack_environment
      @options[:environment] = env
      ENV['RACK_ENV'] = env
    end

    def env
      @options[:environment]       ||
        @cli_options[:environment] ||
        ENV['RACK_ENV']            ||
        'development'
    end

    def prune_bundler?
      @options[:prune_bundler] && clustered? && !@options[:preload_app]
    end

    def close_binder_listeners
      @binder.listeners.each do |l, io|
        io.close
        uri = URI.parse(l)
        next unless uri.scheme == 'unix'
        File.unlink("#{uri.host}#{uri.path}")
      end
    end


    def generate_restart_data
      # Use the same trick as unicorn, namely favor PWD because
      # it will contain an unresolved symlink, useful for when
      # the pwd is /data/releases/current.
      if dir = ENV['PWD']
        s_env = File.stat(dir)
        s_pwd = File.stat(Dir.pwd)

        if s_env.ino == s_pwd.ino and (jruby? or s_env.dev == s_pwd.dev)
          @restart_dir = dir
          @options[:worker_directory] = dir
        end
      end

      @restart_dir ||= Dir.pwd

      @original_argv = @argv.nil? ? "puma" : @argv.dup

      require 'rubygems'

      # if $0 is a file in the current directory, then restart
      # it the same, otherwise add -S on there because it was
      # picked up in PATH.
      #
      if File.exist?($0)
        arg0 = [Gem.ruby, $0]
      else
        arg0 = [Gem.ruby, "-S", $0]
      end

      # Detect and reinject -Ilib from the command line
      lib = File.expand_path "lib"
      arg0[1,0] = ["-I", lib] if $:[0] == lib

      if defined? Puma::WILD_ARGS
        @restart_argv = arg0 + Puma::WILD_ARGS + @original_argv
      else
        @restart_argv = arg0 + @original_argv
      end
    end

    def setup_signals
      begin
        Signal.trap "SIGUSR2" do
          restart
        end
      rescue Exception
        log "*** SIGUSR2 not implemented, signal based restart unavailable!"
      end

      begin
        Signal.trap "SIGUSR1" do
          phased_restart
        end
      rescue Exception
        log "*** SIGUSR1 not implemented, signal based restart unavailable!"
      end

      begin
        Signal.trap "SIGTERM" do
          stop
        end
      rescue Exception
        log "*** SIGTERM not implemented, signal based gracefully stopping unavailable!"
      end

      begin
        Signal.trap "SIGHUP" do
          redirect_io
        end
      rescue Exception
        log "*** SIGHUP not implemented, signal based logs reopening unavailable!"
      end

      if jruby?
        Signal.trap("INT") do
          @status = :exit
          graceful_stop
          exit
        end
      end
    end
  end
end