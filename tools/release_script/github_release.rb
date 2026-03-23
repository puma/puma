# frozen_string_literal: true

module ReleaseScript
  module GithubRelease
    def release_tag(version)
      "v#{version}"
    end

    def release_body_for_version(version)
      extract_history_section(version) || die("Could not find section for #{version} in #{history_file}")
    end

    def release_view(tag)
      optional_json_command("gh", "release", "view", tag, "--repo", repo, "--json", "tagName,isDraft,body,url,assets")
    end

    def ensure_github_release(tag, body, draft:)
      release = release_view(tag)
      return release if release

      info(draft ? "Creating draft GitHub release for #{tag}..." : "Creating GitHub release for #{tag}...")
      with_notes_file(body) do |path|
        command = ["gh", "release", "create", tag, "--repo", repo, "--title", tag, "--notes-file", path]
        command << "--draft" if draft
        run_command(*command)
      end
      release_view(tag)
    end

    def sync_github_release_notes(tag, body, release)
      return release if release.fetch("body", "") == body

      info "Updating GitHub release notes for #{tag}..."
      with_notes_file(body) do |path|
        run_command("gh", "release", "edit", tag, "--repo", repo, "--notes-file", path)
      end
      release_view(tag)
    end

    def publish_github_release(tag, release)
      return release unless release.fetch("isDraft", false)

      info "Publishing GitHub release for #{tag}..."
      run_command("gh", "release", "edit", tag, "--repo", repo, "--draft=false")
      release_view(tag)
    end

    def release_artifacts(version)
      artifacts = [
        "pkg/puma-#{version}.gem",
        "pkg/puma-#{version}-java.gem"
      ]
      missing = artifacts.reject { |artifact| File.file?(artifact) }
      die("Missing release artifact(s): #{missing.join(' ')}") unless missing.empty?
      artifacts
    end

    def upload_github_release_artifacts(tag, version)
      info "Uploading GitHub release artifacts for #{tag}..."
      run_command("gh", "release", "upload", tag, "--repo", repo, "--clobber", *release_artifacts(version))
    end

    def with_notes_file(body)
      Tempfile.create("release-notes") do |file|
        file.write(body)
        file.flush
        yield file.path
      end
    end
  end
end
