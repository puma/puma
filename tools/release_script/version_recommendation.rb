# frozen_string_literal: true

module ReleaseScript
  module VersionRecommendation
    SYSTEM_PROMPT = <<~PROMPT.strip
      You are deciding the semantic version bump for the next Puma release.
      Recommend major if any relevant PR in the release range has the 'breaking change' label.
      Otherwise recommend minor if any commit or PR looks like a feature, new option, new hook,
      new capability, or other user-facing enhancement. Otherwise recommend patch.
      When deciding between patch and minor, prefer minor.
      Return exactly one markdown paragraph for reasoning_markdown, and include markdown links to
      the specific commit URLs that drove the recommendation.
    PROMPT

    AGENT_SCHEMA = JSON.generate(
      type: "object",
      required: %w[bump_type reasoning_markdown],
      additionalProperties: false,
      properties: {
        bump_type: { type: "string", enum: %w[patch minor major] },
        reasoning_markdown: { type: "string", minLength: 1 }
      }
    )

    def recommend_version_bump(last_tag)
      prompt = <<~PROMPT
        Determine the semantic version bump for the next Puma release.

        Return JSON that matches the provided schema.

        Additional guidance:
        - Treat a PR label of 'breaking change' as strong evidence for a major release.
        - If any commit looks like a feature or other user-facing addition, recommend at least minor.
        - If the range is strictly fixes, cleanups, docs, CI, or refactors, recommend patch.
        - In reasoning_markdown, include direct markdown links to the commit URLs that triggered the recommendation.

        #{release_range_commit_context(last_tag)}
      PROMPT

      info "Asking #{agent_cmd} to recommend the version bump..."
      response = json_command(*agent_command, stdin_data: prompt)
      recommendation = response["structured_output"] || response
      bump_type = recommendation["bump_type"]
      reasoning = recommendation["reasoning_markdown"].to_s.strip

      die("#{agent_cmd} returned an invalid bump type") unless %w[patch minor major].include?(bump_type)
      die("#{agent_cmd} returned empty bump reasoning") if reasoning.empty?
      die("#{agent_cmd} must include commit links in its reasoning") unless reasoning.include?("https://github.com/#{repo}/commit/")
      die("#{agent_cmd} must return bump reasoning as a single paragraph") if reasoning.include?("\n\n")

      { "bump_type" => bump_type, "reasoning_markdown" => reasoning }
    end

    def release_range_commit_context(last_tag)
      range = "#{last_tag}..HEAD"
      commits = command_output("git", "log", "--reverse", "--format=%H%x09%s", range).lines(chomp: true)
      lines = ["Repository: #{repo}", "Release range: #{range}", "Commit count: #{commits.length}", "", "Commits in range:"]

      commits.each do |line|
        sha, subject = line.split("\t", 2)
        pr = Array(optional_json_command("gh", "api", "repos/#{repo}/commits/#{sha}/pulls")).first || {}
        labels = Array(pr["labels"]).map { |label| label["name"] }

        lines << "- #{sha[0, 12]} #{subject}"
        lines << "  Commit: https://github.com/#{repo}/commit/#{sha}"
        if pr["number"]
          lines << "  PR: ##{pr['number']} #{pr['title']}"
          lines << "  PR URL: #{pr['html_url']}"
          lines << "  Labels: #{labels.empty? ? 'none' : labels.join(', ')}"
        else
          lines << "  PR: none found"
        end
      end

      lines.join("\n")
    end

    def agent_command
      Shellwords.split(agent_cmd) + [
        "-p",
        "--output-format", "json",
        "--allowedTools", "",
        "--permission-mode", "bypassPermissions",
        "--system-prompt", SYSTEM_PROMPT,
        "--json-schema", AGENT_SCHEMA
      ]
    end
  end
end
