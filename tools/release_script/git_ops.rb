# frozen_string_literal: true

module ReleaseScript
  module GitOps
    def current_version
      File.read(version_file)[/PUMA_VERSION = VERSION = "([^"]+)"/, 1] || die("Could not read current version")
    end

    def last_tag
      tags = command_output("git", "tag", "--sort=-v:refname").lines.map(&:strip)
      tags.find { |tag| tag.match?(/^v\d/) } || die("Could not determine last release tag")
    end

    def bump_version(version, bump_type)
      major, minor, patch = version.split(".").map(&:to_i)

      case bump_type
      when "major" then "#{major + 1}.0.0"
      when "minor" then "#{major}.#{minor + 1}.0"
      when "patch" then "#{major}.#{minor}.#{patch + 1}"
      else die("Unknown bump type: #{bump_type}")
      end
    end

    def ensure_clean_main
      branch = command_output("git", "rev-parse", "--abbrev-ref", "HEAD").strip
      die("Must be on 'main' branch (currently on '#{branch}')") unless branch == "main"
      die("Working directory not clean. Commit or stash first.") unless command_output("git", "status", "--porcelain").strip.empty?

      run_command("git", "fetch", "origin", "--quiet")
      local_sha = command_output("git", "rev-parse", "HEAD").strip
      remote_sha = command_output("git", "rev-parse", "origin/main").strip
      die("Local main differs from origin/main. Pull or push first.") unless local_sha == remote_sha
    end

    def check_ci
      info "Checking CI status for HEAD..."
      sha = command_output("git", "rev-parse", "HEAD").strip
      response = optional_json_command("gh", "api", "repos/#{repo}/commits/#{sha}/check-runs")
      status = check_run_status(response)

      case status
      when "success" then info("CI is green.")
      when "pending" then warn("CI is still running. Proceed with caution.")
      when "failure" then warn("CI has failures. You may want to investigate before releasing.")
      else warn("Could not determine CI status.")
      end
    end

    def check_run_status(response)
      return "unknown" unless response

      conclusions = Array(response["check_runs"]).filter_map { |run| run["conclusion"] }
      return "pending" if conclusions.empty?

      conclusions.all?("success") ? "success" : "failure"
    end

    def top_contributors_since(tag)
      command_output("git", "shortlog", "-s", "-n", "--no-merges", "#{tag}..HEAD").lines.map(&:rstrip)
    end

    def codename_earner(tag)
      top_contributors_since(tag).first.to_s.sub(/^\s*\d+\s*/, "")
    end

    def get_user_name(login)
      user = optional_json_command("gh", "api", "users/#{login}")
      user&.fetch("name", nil).to_s.empty? ? login : user["name"]
    end

    def ensure_release_tag_pushed(tag)
      head_sha = command_output("git", "rev-parse", "HEAD").strip
      local_tag_sha = optional_output("git", "rev-parse", "-q", "--verify", "refs/tags/#{tag}^{commit}")
      remote_tag_sha = command_output("git", "ls-remote", "--refs", "--tags", "origin", "refs/tags/#{tag}").split.first.to_s

      if !remote_tag_sha.empty?
        die("Remote tag #{tag} already exists at #{remote_tag_sha}, not HEAD #{head_sha}. Fix the tag before building.") unless remote_tag_sha == head_sha
        info "Remote tag #{tag} already points at HEAD."
        return
      end

      if !local_tag_sha.empty? && local_tag_sha != head_sha
        die("Local tag #{tag} already exists at #{local_tag_sha}, not HEAD #{head_sha}. Fix the tag before building.")
      end

      run_command("git", "tag", "--no-sign", tag) if local_tag_sha.empty?
      run_command("git", "push", "origin", tag)
    end
  end
end
