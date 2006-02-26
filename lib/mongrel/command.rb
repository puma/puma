require 'singleton'
require 'optparse'
require 'pluginfactory'


module Mongrel

  # Contains all of the various commands that are used with 
  # Mongrel servers.

  module Command


    # A Command pattern implementation used to create the set of command available to the user
    # from Mongrel.  The script uses objects which implement this interface to do the
    # user's bidding.
    #
    # Creating a new command is very easy, and you can do it without modifying the source
    # of Mongrel thanks to PluginFactory.  What you do is the following:
    #
    # 1.  
    class Command
      include PluginFactory
      
      attr_reader :valid, :done_validating

      # Called by the implemented command to set the options for that command.
      # Every option has a short and long version, a description, a variable to
      # set, and a default value.  No exceptions.
      def options(opts)
        # process the given options array
        opts.each do |short, long, help, variable, default|
          self.instance_variable_set(variable, default)
          @opt.on(short, long, help) do |arg|
            self.instance_variable_set(variable, arg)
          end
        end
      end

      # Called by the subclass to setup the command and parse the argv arguments.
      # The call is destructive on argv since it uses the OptionParser#parse! function.
      def initialize(argv)
        @opt = OptionParser.new
        @valid = true
        # this is retarded, but it has to be done this way because -h and -v exit
        @done_validating = false
        @original_args = argv.dup

        configure

        # I need to add my own -h definition to prevent the -h by default from exiting.
        @opt.on_tail("-h", "--help", "Show this message") do
          @done_validating = true
          puts @opt
        end
        
        # I need to add my own -v definition to prevent the -h from exiting by default as well.
        @opt.on_tail("--version", "Show version") do
          @done_validating = true
          if VERSION
            puts "Version #{VERSION}"
          end
        end
        
        @opt.parse! argv
      end
      
      # Tells the PluginFactory where to look for additional commands.  By default
      # it's just a "plugins" directory wherever we are located.
      def self.derivativeDirs
        return ["plugins"]
      end
      
      # Returns true/false depending on whether the command is configured properly.
      def validate
        return @valid
      end
      
      # Returns a help message.  Defaults to OptionParser#help which should be good.
      def help
        @opt.help
      end
      
      # Runs the command doing it's job.  You should implement this otherwise it will
      # throw a NotImplementedError as a reminder.
      def run
        raise NotImplementedError
      end
      
      
      # Validates the given expression is true and prints the message if not, exiting.
      def valid?(exp, message)
        if not @done_validating and (not exp)
          failure message
          @valid = false
          @done_validating = true
        end
      end

      # Validates that a file exists and if not displays the message
      def valid_exists?(file, message)
        valid?(file != nil && File.exist?(file), message)
      end
      
      
      # Validates that the file is a file and not a directory or something else.
      def valid_file?(file, message)
        valid?(file != nil && File.file?(file), message)
      end
      
      # Validates that the given directory exists
      def valid_dir?(file, message)
        valid?(file != nil && File.directory?(file), message)
      end

      # Just a simple method to display failure until something better is developed.
      def failure(message)
        STDERR.puts "!!! #{message}"
      end
    end
    
    
    
    # A Singleton class that manages all of the available commands
    # and handles running them.
    class Registry
      include Singleton
      
      # Builds a list of possible commands from the Command derivates list
      def commands
        list = Command.derivatives()
        match = Regexp.new("(.*::.*)|(.*command.*)", Regexp::IGNORECASE)
        
        results = []
        list.keys.each do |key|
          results << key.to_s unless match.match(key.to_s)
        end
        
        return results.sort
      end

      # Prints a list of available commands.
      def print_command_list
        puts "Available commands are:\n\n"
        
        self.commands.each do |name|
          puts " - #{name}\n"
        end
        
        puts "\nEach command takes -h as an option to get help."
        
      end
      
      
      # Runs the args against the first argument as the command name.
      # If it has any errors it returns a false, otherwise it return true.
      def run(args)
        # find the command
        cmd_name = args.shift
        
        if !cmd_name or cmd_name == "?" or cmd_name == "help"
          print_command_list
          return true
        end
        
        # command exists, set it up and validate it
        begin
          command = Command.create(cmd_name, args)
        rescue FactoryError
          STDERR.puts "INVALID COMMAND: #$!"
          print_command_list
          return
        end
        
        # Normally the command is NOT valid right after being created
        # but sometimes (like with -h or -v) there's no further processing
        # needed so the command is already valid so we can skip it.
        if not command.done_validating
          if not command.validate
            STDERR.puts "#{cmd_name} reported an error. Use -h to get help."
            return false
          else
            command.run
          end
        end
        return true
      end
      
    end
  end
end

