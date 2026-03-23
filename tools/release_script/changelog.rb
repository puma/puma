# frozen_string_literal: true

module ReleaseScript
  module Changelog
    CATEGORY_ORDER = {
      "Features" => 1,
      "Bugfixes" => 2,
      "Performance" => 3,
      "Refactor" => 4,
      "Docs" => 5,
      "CI" => 6,
      "Breaking changes" => 7
    }.freeze
    CATEGORY_REGEX = /^\* (#{Regexp.union(CATEGORY_ORDER.keys).source})$/
    ITEM_REGEX = /^  \* .+ \(\[#(\d+)\](, \[#(\d+)\])*\)$/
    INLINE_LINK_REGEX = /\[[^\]]+\]\(/

    def validate_changelog_format(changelog)
      state = :category
      current_category = nil
      last_category_order = 0
      category_count = 0
      item_count = 0
      seen_categories = {}
      errors = []

      changelog.each_line(chomp: true).with_index(1) do |raw_line, line_number|
        line = raw_line.delete_suffix("\r")

        if line.empty?
          errors << "Line #{line_number}: category '* #{current_category}' must contain at least one item." if state == :item
          state = :category if %i[item item_or_blank].include?(state)
          next
        end

        if line.start_with?("#")
          errors << "Line #{line_number}: headings are not allowed in the changelog body."
          next
        end

        if (match = line.match(CATEGORY_REGEX))
          category = match[1]
          current_order = CATEGORY_ORDER.fetch(category)
          errors << "Line #{line_number}: category '* #{current_category}' must contain at least one item before the next category." if state == :item
          errors << "Line #{line_number}: blank line required between categories." if state != :category && state != :item
          errors << "Line #{line_number}: categories must appear in this order: #{CATEGORY_ORDER.keys.join(', ')}." if current_order < last_category_order
          errors << "Line #{line_number}: duplicate category '* #{category}'." if seen_categories[category]

          seen_categories[category] = true
          current_category = category
          last_category_order = current_order
          category_count += 1
          state = :item
          next
        end

        errors << "Line #{line_number}: inline markdown links are not allowed; use reference-style PR refs like ([#123])." if line.match?(INLINE_LINK_REGEX)

        if line.match?(ITEM_REGEX)
          errors << "Line #{line_number}: changelog items must appear under a category heading." unless %i[item item_or_blank].include?(state)
          item_count += 1
          state = :item_or_blank
          next
        end

        if line.start_with?("*")
          errors << "Line #{line_number}: unsupported category. Allowed categories: #{CATEGORY_ORDER.keys.join(', ')}."
        else
          errors << "Line #{line_number}: unexpected content. Expected a category heading or an item like '  * Description ([#123])'."
        end
      end

      errors << "Line #{changelog.lines.count}: category '* #{current_category}' must contain at least one item." if state == :item
      errors << "Changelog must contain at least one category." if category_count.zero?
      errors << "Changelog must contain at least one changelog item." if item_count.zero?
      errors
    end

    def generate_changelog(new_tag, last_tag)
      max_attempts = env.fetch("CHANGELOG_MAX_ATTEMPTS", "5").to_i
      last_changelog = nil
      last_errors = []
      env_overrides = github_token.empty? ? {} : { "GITHUB_TOKEN" => github_token }

      1.upto(max_attempts) do |attempt|
        info "Generating changelog with communiqué (attempt #{attempt}/#{max_attempts})..."
        result = run_command("communique", "generate", new_tag, last_tag, "--concise", "--dry-run", "--config", communique_config_file, env_overrides:, allow_failure: true)
        die("communiqué failed. Is ANTHROPIC_API_KEY set?") unless result.fetch(:success)

        last_changelog = result.fetch(:stdout)
        last_errors = validate_changelog_format(last_changelog)
        return last_changelog if last_errors.empty?

        warn "Generated changelog did not match the required format:"
        last_errors.each { |message| warn message }
      end

      message = [
        "communiqué could not produce a valid changelog after #{max_attempts} attempts.",
        *last_errors,
        "Last invalid changelog output:",
        last_changelog.to_s
      ].join("\n")
      die message
    end

    def generate_all_link_refs(changelog)
      numbers = changelog.scan(/\[#(\d+)\]/).flatten.map(&:to_i).uniq.sort.reverse
      existing_history = File.read(history_file)
      refs = numbers.filter_map do |number|
        next if existing_history.match?(/^\[##{number}\]:/)

        info "  Looking up ##{number}..."
        generate_link_ref(number)
      end
      refs.join("\n")
    end

    def extract_history_section(version)
      lines = File.readlines(history_file, chomp: true)
      start_index = lines.index { |line| line.match?(/^## #{Regexp.escape(version)} /) }
      return nil unless start_index

      section = lines[(start_index + 1)..].take_while { |line| !line.start_with?("## ") }
      section.join("\n").strip
    end

    def prepend_history_section(version, changelog, link_refs)
      header = "## #{version} / #{Date.today.strftime('%Y-%m-%d')}"
      content = "#{header}\n\n#{changelog}\n\n#{File.read(history_file)}"
      File.write(history_file, content)
      insert_link_refs(link_refs)
    end

    def update_version_file(new_version, bump_type)
      content = File.read(version_file).sub(/PUMA_VERSION = VERSION = ".*"/, "PUMA_VERSION = VERSION = \"#{new_version}\"")
      content = content.sub(/CODE_NAME = ".*"/, 'CODE_NAME = "PUT CODENAME HERE"') unless bump_type == "patch"
      File.write(version_file, content)
    end

    def insert_link_refs(refs)
      return if refs.empty?

      lines = File.readlines(history_file, chomp: true)
      index = lines.index { |line| line.match?(/^\[#\d+\]:/) }

      if index
        updated = [*lines[0...index], *refs.lines(chomp: true), *lines[index..]].join("\n")
      else
        updated = "#{File.read(history_file)}\n#{refs}"
      end

      File.write(history_file, "#{updated}\n")
    end

    def generate_link_ref(number)
      if (data = optional_json_command("gh", "pr", "view", number.to_s, "--repo", repo, "--json", "mergedAt,author"))
        login = data.dig("author", "login")
        merged_at = data["mergedAt"].to_s.split("T").first
        author_name = get_user_name(login)
        return "[##{number}]:https://github.com/#{repo}/pull/#{number}     \"PR by #{author_name}, merged #{merged_at}\""
      end

      if (data = optional_json_command("gh", "issue", "view", number.to_s, "--repo", repo, "--json", "closedAt,author"))
        login = data.dig("author", "login")
        closed_at = data["closedAt"].to_s.split("T").first
        return "[##{number}]:https://github.com/#{repo}/issues/#{number}     \"Issue by @#{login}, closed #{closed_at}\""
      end

      warn "Could not look up ##{number}"
      nil
    end
  end
end
