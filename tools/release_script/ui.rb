# frozen_string_literal: true

module ReleaseScript
  module UI
    GREEN = "\e[0;32m"
    YELLOW = "\e[1;33m"
    RED = "\e[0;31m"
    NC = "\e[0m"

    def info(message)
      $stdout.puts "#{GREEN}==>#{NC} #{message}"
    end

    def warn(message)
      $stdout.puts "#{YELLOW}==>#{NC} #{message}"
    end

    def error(message)
      $stderr.puts "#{RED}==>#{NC} #{message}"
    end

    def die(message)
      raise Error, message
    end

    def usage
      $stdout.puts <<~USAGE
        Usage: #{File.basename($PROGRAM_NAME)} <command>

        Commands:
          prepare   Generate changelog, bump version, open release PR, create draft release
          build     Tag release and build gem files
          github    Sync, publish, and upload assets for the GitHub release
      USAGE
      exit 1
    end
  end
end
