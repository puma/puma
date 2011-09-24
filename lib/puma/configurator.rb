require 'yaml'
require 'etc'

require 'rack/builder'

module Puma
  # Implements a simple DSL for configuring a Puma server for your 
  # purposes.  More used by framework implementers to setup Puma
  # how they like, but could be used by regular folks to add more things
  # to an existing puma configuration.
  #
  # It is used like this:
  #
  #   require 'puma'
  #   config = Puma::Configurator.new :host => "127.0.0.1" do
  #     listener :port => 3000 do
  #       uri "/app", :handler => Puma::DirHandler.new(".", load_mime_map("mime.yaml"))
  #     end
  #     run
  #   end
  # 
  # This will setup a simple DirHandler at the current directory and load additional
  # mime types from mimy.yaml.  The :host => "127.0.0.1" is actually not 
  # specific to the servers but just a hash of default parameters that all 
  # server or uri calls receive.
  #
  # When you are inside the block after Puma::Configurator.new you can simply
  # call functions that are part of Configurator (like server, uri, daemonize, etc)
  # without having to refer to anything else.  You can also call these functions on 
  # the resulting object directly for additional configuration.
  #
  # A major thing about Configurator is that it actually lets you configure 
  # multiple listeners for any hosts and ports you want.  These are kept in a
  # map config.listeners so you can get to them.
  #
  # * :pid_file => Where to write the process ID.
  class Configurator
    attr_reader :listeners
    attr_reader :defaults
    attr_reader :needs_restart

    # You pass in initial defaults and then a block to continue configuring.
    def initialize(defaults={}, &block)
      @listener = nil
      @listener_name = nil
      @listeners = {}
      @defaults = defaults
      @needs_restart = false
      @pid_file = defaults[:pid_file]

      if block
        yield self
      end
    end

    # Change privileges of the process to specified user and group.
    def change_privilege(user, group)
      begin
        uid, gid = Process.euid, Process.egid
        target_uid = Etc.getpwnam(user).uid if user
        target_gid = Etc.getgrnam(group).gid if group

        if uid != target_uid or gid != target_gid
          log "Initiating groups for #{user.inspect}:#{group.inspect}."
          Process.initgroups(user, target_gid)
        
          log "Changing group to #{group.inspect}."
          Process::GID.change_privilege(target_gid)

          log "Changing user to #{user.inspect}." 
          Process::UID.change_privilege(target_uid)
        end
      rescue Errno::EPERM => e
        log "Couldn't change user and group to #{user.inspect}:#{group.inspect}: #{e.to_s}."
        log "Puma failed to start."
        exit 1
      end
    end

    def remove_pid_file
      File.unlink(@pid_file) if @pid_file and File.exists?(@pid_file)
    end

    # Writes the PID file if we're not on Windows.
    def write_pid_file
      unless RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
        log "Writing PID file to #{@pid_file}"
        open(@pid_file,"w") {|f| f.write(Process.pid) }
        open(@pid_file,"w") do |f|
          f.write(Process.pid)
          File.chmod(0644, @pid_file)
        end
      end
    end

    # This will resolve the given options against the defaults.
    # Normally just used internally.
    def resolve_defaults(options)
      options.merge(@defaults)
    end

    # Starts a listener block.  This is the only one that actually takes
    # a block and then you make Configurator.uri calls in order to setup
    # your URIs and handlers.  If you write your Handlers as GemPlugins
    # then you can use load_plugins and plugin to load them.
    # 
    # It expects the following options (or defaults):
    # 
    # * :host => Host name to bind.
    # * :port => Port to bind.
    # * :user => User to change to, must have :group as well.
    # * :group => Group to change to, must have :user as well.
    #
    def listener(options={})
      raise "Cannot call listener inside another listener block." if (@listener or @listener_name)
      ops = resolve_defaults(options)

      @listener = Puma::Server.new(ops[:host], ops[:port].to_i, ops[:concurrency].to_i)
      @listener_name = "#{ops[:host]}:#{ops[:port]}"
      @listeners[@listener_name] = @listener

      if ops[:user] and ops[:group]
        change_privilege(ops[:user], ops[:group])
      end

      yield self if block_given?

      # all done processing this listener setup, reset implicit variables
      @listener = nil
      @listener_name = nil
    end

    def load_rackup(file)
      app, options = Rack::Builder.parse_file file

      @listener.app = app
      # Do something with options?
    end

    # Uses the GemPlugin system to easily load plugins based on their
    # gem dependencies.  You pass in either an :includes => [] or 
    # :excludes => [] setting listing the names of plugins to include
    # or exclude from the determining the dependencies.
    def load_plugins(options={})
      ops = resolve_defaults(options)

      load_settings = {}
      if ops[:includes]
        ops[:includes].each do |plugin|
          load_settings[plugin] = GemPlugin::INCLUDE
        end
      end

      if ops[:excludes]
        ops[:excludes].each do |plugin|
          load_settings[plugin] = GemPlugin::EXCLUDE
        end
      end

      GemPlugin::Manager.instance.load(load_settings)
    end


    # Easy way to load a YAML file and apply default settings.
    def load_yaml(file, default={})
      default.merge(YAML.load_file(file))
    end

    # Loads and creates a plugin for you based on the given
    # name and configured with the selected options.  The options
    # are merged with the defaults prior to passing them in.
    def plugin(name, options={})
      ops = resolve_defaults(options)
      GemPlugin::Manager.instance.create(name, ops)
    end

    # Lets you do redirects easily as described in Puma::RedirectHandler.
    # You use it inside the configurator like this:
    #
    #   redirect("/test", "/to/there") # simple
    #   redirect("/to", /t/, 'w') # regexp
    #   redirect("/hey", /(w+)/) {|match| ...}  # block
    #
    def redirect(from, pattern, replacement = nil, &block)
      uri from, :handler => Puma::RedirectHandler.new(pattern, replacement, &block)
    end

    # Works like a meta run method which goes through all the 
    # configured listeners.  Use the Configurator.join method
    # to prevent Ruby from exiting until each one is done.
    def run
      @listeners.each {|name,s| 
        s.run 
      }
    end

    # Calls .stop on all the configured listeners so they
    # stop processing requests (gracefully).  By default it
    # assumes that you don't want to restart.
    def stop(needs_restart=false, synchronous=false)   
      @listeners.each do |name,s| 
        s.stop(synchronous)      
      end      
      @needs_restart = needs_restart
    end


    # This method should actually be called *outside* of the
    # Configurator block so that you can control it.  In other words
    # do it like:  config.join.
    def join
      @listeners.values.each {|s| s.acceptor.join }
    end

    # Used to allow you to let users specify their own configurations
    # inside your Configurator setup.  You pass it a script name and
    # it reads it in and does an eval on the contents passing in the right
    # binding so they can put their own Configurator statements.
    def run_config(script)
      open(script) {|f| eval(f.read, proc {self}.binding) }
    end

    # Sets up the standard signal handlers that are used on most Ruby
    # It only configures if the platform is not win32 and doesn't do
    # a HUP signal since this is typically framework specific.
    #
    # Requires a :pid_file option given to Configurator.new to indicate a file to delete.  
    # It sets the PumaConfig.needs_restart attribute if 
    # the start command should reload.  It's up to you to detect this
    # and do whatever is needed for a "restart".
    #
    # This command is safely ignored if the platform is win32 (with a warning)
    def setup_signals(options={})
      ops = resolve_defaults(options)

      # forced shutdown, even if previously restarted (actually just like TERM but for CTRL-C)
      trap("INT") { log "INT signal received."; stop(false) }

      # clean up the pid file always
      at_exit { remove_pid_file }

      unless RbConfig::CONFIG['host_os'] =~ /mingw|mswin/
        # graceful shutdown
        trap("TERM") { log "TERM signal received."; stop }
        trap("USR1") { log "USR1 received, toggling $puma_debug_client to #{!$puma_debug_client}"; $puma_debug_client = !$puma_debug_client }
        # restart
        trap("USR2") { log "USR2 signal received."; stop(true) }

        log "Signals ready.  TERM => stop.  USR2 => restart.  INT => stop (no restart)."
      else
        log "Signals ready.  INT => stop (no restart)."
      end
    end

    # Logs a simple message to STDERR (or the puma log if in daemon mode).
    def log(msg)
      STDERR.print "** ", msg, "\n"
    end

  end
end
