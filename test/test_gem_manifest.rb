# frozen_string_literal: true

require_relative "helper"

class TestGemManifest < PumaTest
  SHIPPED = %w[
    History.md
    LICENSE
    README.md
    bin/puma
    bin/puma-wild
    bin/pumactl
    docs/**/*
    ext/puma_http11/extconf.rb
    ext/puma_http11/*.{c,h}
    lib/**/*.rb
  ].freeze

  NOT_SHIPPED = %w[
    .agents/**/*
    .codeclimate.yml
    .gitattributes
    .github/**/*
    .gitignore
    .rubocop.yml
    .rubocop_todo.yml
    CODE_OF_CONDUCT.md
    CONTRIBUTING.md
    GOVERNANCE.md
    Gemfile
    MAINTAINERS
    Rakefile
    Release.md
    SECURITY.md
    benchmarks/**/*
    cops/**/*
    examples/**/*
    ext/puma_http11/*.rl
    ext/puma_http11/**/*.java
    puma.gemspec
    test/**/*
    tools/**/*
  ].freeze

  FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

  def setup
    @root = File.expand_path("..", __dir__)
    @tracked = Dir.chdir(@root) { `git ls-files -z`.split("\0") }
    skip "not a git checkout" if @tracked.empty?
  end

  def test_every_tracked_file_is_classified_exactly_once
    unclassified = @tracked.reject { |f| matches?(SHIPPED, f) || matches?(NOT_SHIPPED, f) }
    ambiguous = @tracked.select { |f| matches?(SHIPPED, f) && matches?(NOT_SHIPPED, f) }

    assert_empty unclassified, "Add these files to SHIPPED or NOT_SHIPPED in #{__FILE__}"
    assert_empty ambiguous, "These files match both SHIPPED and NOT_SHIPPED in #{__FILE__}"
  end

  def test_gemspec_ships_exactly_the_shipped_files
    spec = Dir.chdir(@root) { Gem::Specification.load("puma.gemspec") }
    expected = @tracked.select { |f| matches?(SHIPPED, f) }

    assert_equal expected.sort, spec.files.sort
  end

  def test_every_pattern_matches_a_tracked_file
    unused = (SHIPPED + NOT_SHIPPED).reject { |pattern| @tracked.any? { |f| File.fnmatch?(pattern, f, FLAGS) } }

    assert_empty unused, "Remove stale patterns from #{__FILE__}"
  end

  private

  def matches?(patterns, file)
    patterns.any? { |pattern| File.fnmatch?(pattern, file, FLAGS) }
  end
end
