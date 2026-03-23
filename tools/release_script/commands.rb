# frozen_string_literal: true

module ReleaseScript
  module Commands
    def run
      case argv.first
      when "prepare" then cmd_prepare
      when "build" then cmd_build
      when "github" then cmd_github
      else usage
      end
    rescue Error => e
      error e.message
      exit 1
    end

    def cmd_prepare
      check_deps("git", "gh", "communique", agent_binary)
      ensure_clean_main
      check_ci

      last = last_tag
      info "Last release tag: #{last}"
      puts

      recommendation = recommend_version_bump(last)
      bump_type = recommendation.fetch("bump_type")
      bump_reasoning = recommendation.fetch("reasoning_markdown")

      puts
      info "Recommended version bump: #{bump_type}"
      puts bump_reasoning
      puts

      current = current_version
      new_version = bump_version(current, bump_type)
      info "Version bump: #{current} -> #{new_version}"

      earner = prepare_codename_earner(last, bump_type)
      changelog = prepare_changelog(new_version, last)

      puts
      info "Generated changelog:"
      puts "---"
      puts changelog
      puts "---"
      puts

      info "Generating link references..."
      link_refs = generate_all_link_refs(changelog)
      info "Updating #{history_file}..."
      prepend_history_section(new_version, changelog, link_refs)
      info "Updating #{version_file}..."
      update_version_file(new_version, bump_type)

      branch = "release-v#{new_version}"
      info "Creating branch #{branch}..."
      run_command("git", "checkout", "-b", branch)
      run_command("git", "add", version_file, history_file)
      run_command("git", "commit", "--no-gpg-sign", "-m", "Release v#{new_version}")
      run_command("git", "push", "-u", "origin", branch)

      info "Creating pull request..."
      pr_url = command_output("gh", "pr", "create", "--repo", repo, "--title", "Release v#{new_version}", "--body", prepare_pr_body(bump_type, bump_reasoning, earner)).strip
      release = ensure_github_release(release_tag(new_version), release_body_for_version(new_version), draft: true)
      release = sync_github_release_notes(release_tag(new_version), release_body_for_version(new_version), release)

      puts
      info "Release PR created: #{pr_url}"
      info "Draft GitHub release ready: #{release.fetch('url')}"
      warn "Waiting on @#{earner} for a codename before merging." if earner
      puts
      puts "Next steps:"
      puts "  1. Review and merge the PR"
      puts "  2. Run: tools/release_script.sh build"
    end

    def cmd_build
      check_deps("git", "gh", "bundle")
      ensure_clean_main

      version = current_version
      tag = release_tag(version)
      info "Building Puma #{version}..."
      info "Ensuring tag #{tag} points at HEAD and is pushed..."
      ensure_release_tag_pushed(tag)
      info "Building MRI gem..."
      run_command("bundle", "exec", "rake", "build")

      puts
      info "Built: pkg/puma-#{version}.gem"
      jruby_built = build_jruby_gem_with_mise(version)

      unless jruby_built
        puts
        warn "mise not found; JRuby gem was not built automatically."
        puts "To build the JRuby gem manually:"
        puts "  1. Install mise or switch to JRuby yourself"
        puts "  2. Run: rake java gem"
      end

      puts
      puts "Then push:"
      puts "  gem push pkg/puma-#{version}.gem"
      puts "  gem push pkg/puma-#{version}-java.gem"
      puts
      puts "After pushing, run: tools/release_script.sh github"
    end

    def cmd_github
      check_deps("gh")

      version = current_version
      tag = release_tag(version)
      body = release_body_for_version(version)
      release = ensure_github_release(tag, body, draft: true)
      release = sync_github_release_notes(tag, body, release)
      release = publish_github_release(tag, release)
      upload_github_release_artifacts(tag, version)
      info "GitHub release published: #{release.fetch('url')}"
    end

    def prepare_codename_earner(last, bump_type)
      return nil if bump_type == "patch"

      puts
      info "Top contributors since #{last}:"
      puts top_contributors_since(last).first(5)
      earner = codename_earner(last)
      puts
      info "Codename earner: #{earner}"
      earner
    end

    def prepare_changelog(new_version, last)
      tag = release_tag(new_version)
      info "Creating temporary tag #{tag}..."
      run_command("git", "tag", tag, "HEAD")
      generate_changelog(tag, last)
    ensure
      run_command("git", "tag", "-d", tag, allow_failure: true) if tag
    end

    def prepare_pr_body(bump_type, bump_reasoning, earner)
      body = <<~BODY
        ## Version bump recommendation

        Recommended bump: **#{bump_type}**

        #{bump_reasoning}
      BODY
      return body unless earner

      body + <<~BODY

        ## Codename

        @#{earner} earned the codename for this release. Please propose a codename!
      BODY
    end
  end
end
