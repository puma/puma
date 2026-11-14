# frozen_string_literal: true

require_relative "helper"
require_relative "gem_manifest"

class TestGemManifest < PumaTest
  include PumaGemManifest

  def setup
    @root = File.expand_path("..", __dir__)
    @tracked = Dir.chdir(@root) { `git ls-files -z`.split("\0") }
    skip "not a git checkout" if @tracked.empty?
  end

  def test_every_tracked_file_is_classified_exactly_once
    unclassified = @tracked.reject { |f| matches?(SHIPPED, f) || matches?(NOT_SHIPPED, f) }
    ambiguous = @tracked.select { |f| matches?(SHIPPED, f) && matches?(NOT_SHIPPED, f) }

    assert_empty unclassified, "Add these files to SHIPPED or NOT_SHIPPED in test/gem_manifest.rb"
    assert_empty ambiguous, "These files match both SHIPPED and NOT_SHIPPED in test/gem_manifest.rb"
  end

  def test_gemspec_ships_exactly_the_shipped_files
    spec = Dir.chdir(@root) { Gem::Specification.load("puma.gemspec") }

    assert_equal shipped(@tracked), spec.files.sort
  end

  def test_every_pattern_matches_a_tracked_file
    unused = (SHIPPED + NOT_SHIPPED).reject { |pattern| @tracked.any? { |f| File.fnmatch?(pattern, f, FLAGS) } }

    assert_empty unused, "Remove stale patterns from test/gem_manifest.rb"
  end
end
