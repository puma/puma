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

    attr_accessor :options, :binder, :config, :events
    ## THIS STUFF IS NEEDED FOR RUNNER

    def setup(options)
      @options = options
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
      # remove eventually
      IS_JRUBY
    end

    def windows?
      # remove eventually
      RUBY_PLATFORM =~ /mswin32|ming32/
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