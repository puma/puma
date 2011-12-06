module Puma
  class Configuration
    DefaultTCPHost = "0.0.0.0"
    DefaultTCPPort = 9292

    def initialize(options)
      @options = options
      @options[:binds] ||= []
    end

    attr_reader :options

    def load
      if path = @options[:config_file]
        instance_eval File.read(path), path, 1
      end

      # Rakeup default option support
      if host = @options[:Host]
        port = @options[:Port] || DefaultTCPPort

        @options[:binds] << "tcp://#{host}:#{port}"
      end

      if @options[:binds].empty?
        @options[:binds] << "tcp://#{DefaultTCPHost}:#{DefaultTCPPort}"
      end
    end

    def self.temp_path
      require 'tmpdir'

      t = (Time.now.to_f * 1000).to_i
      "#{Dir.tmpdir}/puma-status-#{t}-#{$$}"
    end

    # Use +obj+ or +block+ as the Rack app. This allows a config file to
    # be the app itself.
    #
    def app(obj=nil, &block)
      obj ||= block

      raise "Provide either a #call'able or a block" unless obj

      @options[:app] = obj
    end

    # Start the Puma control rack app on +url+. This app can be communicated
    # with to control the main server.
    #
    def activate_control_app(url="auto")
      @options[:control_url] = url
    end

    # Bind the server to +url+. tcp:// and unix:// are the only accepted
    # protocols.
    #
    def bind(url)
      @options[:binds] << url
    end

    # Store the pid of the server in the file at +path+.
    def pidfile(path)
      @options[:pidfile] = path
    end

    # Disable request logging.
    #
    def quiet
      @options[:quiet] = true
    end

    # Load +path+ as a rackup file.
    #
    def rackup(path)
      @options[:rackup] = path.to_s
    end

    # Configure +min+ to be the minimum number of threads to use to answer
    # requests and +max+ the maximum.
    #
    def threads(min, max)
      if min > max
        raise "The minimum number of threads must be less than the max"
      end

      @options[:min_threads] = min
      @options[:max_threads] = max
    end

    # Use +path+ as the file to store the server info state. This is
    # used by pumactl to query and control the server.
    #
    def state_path(path)
      @options[:state] = path.to_s
    end
  end
end
