# frozen_string_literal: true

module ReleaseScript
  module BuildSupport
    def build_jruby_gem_with_mise(version)
      return false unless command_available?("mise")

      jruby_version = command_output("mise", "latest", "jruby").strip
      die("Could not determine latest JRuby version from mise") if jruby_version.empty?

      info "Building JRuby gem with mise and jruby@#{jruby_version}..."
      run_command("mise", "exec", "jruby@#{jruby_version}", "--", "rake", "java", "gem")
      info "Built: pkg/puma-#{version}-java.gem"
      true
    end
  end
end
