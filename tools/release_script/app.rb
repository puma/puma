# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"
require "tempfile"
require "date"

require_relative "ui"
require_relative "git_ops"
require_relative "changelog"
require_relative "github_release"
require_relative "version_recommendation"
require_relative "build_support"
require_relative "commands"

module ReleaseScript
  class Error < StandardError; end

  class App
    include UI
    include GitOps
    include Changelog
    include GithubRelease
    include VersionRecommendation
    include BuildSupport
    include Commands

    REPO = "puma/puma"
    VERSION_FILE = "lib/puma/const.rb"
    HISTORY_FILE = "History.md"
    COMMUNIQUE_CONFIG_FILE = "tools/communique.toml"

    attr_reader :argv, :env

    def initialize(argv, env: ENV)
      @argv = argv
      @env = env
    end

    def repo = REPO
    def version_file = VERSION_FILE
    def history_file = HISTORY_FILE
    def communique_config_file = COMMUNIQUE_CONFIG_FILE
    def agent_cmd = env.fetch("AGENT_CMD", "claude")

    def agent_binary
      Shellwords.split(agent_cmd).first || "claude"
    end

    def check_deps(*commands)
      missing = commands.flatten.compact.uniq.reject { |command| command_available?(command) }
      die "Missing required dependencies: #{missing.join(" ")}" unless missing.empty?
    end

    def command_available?(command)
      env.fetch("PATH", "").split(File::PATH_SEPARATOR).any? do |path|
        candidate = File.join(path, command)
        File.file?(candidate) && File.executable?(candidate)
      end
    end

    def run_command(*command, stdin_data: nil, env_overrides: {}, allow_failure: false)
      stdout, stderr, status = Open3.capture3(env.to_h.merge(env_overrides), *command, stdin_data: stdin_data)
      result = { stdout: stdout, stderr: stderr, success: status.success?, exitstatus: status.exitstatus }
      return result if result[:success] || allow_failure

      details = result[:stderr].strip
      details = result[:stdout].strip if details.empty?
      die [command.join(" "), details].reject(&:empty?).join(": ")
    end

    def command_output(*command, **options)
      run_command(*command, **options).fetch(:stdout)
    end

    def optional_output(*command)
      run_command(*command, allow_failure: true).fetch(:stdout).strip
    end

    def json_command(*command, **options)
      output = command_output(*command, **options).strip
      output.empty? ? {} : JSON.parse(output)
    end

    def optional_json_command(*command)
      result = run_command(*command, allow_failure: true)
      return nil unless result.fetch(:success)

      output = result.fetch(:stdout).strip
      output.empty? ? {} : JSON.parse(output)
    end

    def github_token
      return @github_token if defined?(@github_token)

      token = env.fetch("GITHUB_TOKEN", "")
      token = optional_output("gh", "auth", "token") if token.empty?
      @github_token = token
    end
  end
end
