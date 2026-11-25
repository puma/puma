# frozen_string_literal: true

module PumaGemManifest
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
    .duel.rb
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
    duel/**/*
    ext/puma_http11/*.rl
    ext/puma_http11/**/*.java
    puma.gemspec
    test/**/*
    tools/**/*
  ].freeze

  JAVA_EXTENSION = "lib/puma/puma_http11.jar"

  FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

  module_function

  def matches?(patterns, file)
    patterns.any? { |pattern| File.fnmatch?(pattern, file, FLAGS) }
  end

  def shipped(tracked, platform: "ruby")
    files = tracked.select { |f| matches?(SHIPPED, f) }
    files = files.reject { |f| f.start_with?("ext/") } + [JAVA_EXTENSION] if platform == "java"
    files.sort
  end
end
