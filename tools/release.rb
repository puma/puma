# frozen_string_literal: true

require "date"
require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "ruby-gem-release/tasks"
require "ruby-gem-release/package/ruby_gem"
require "ruby-gem-release/package/prebuilt"
require "ruby-gem-release/package/collection"
require "ruby-gem-release/package/content_audit"
require "ruby-gem-release/changelog/notes"
require "ruby-gem-release/hosting/github_release"
require "ruby-gem-release/workflow/reviewed_ruby_gem"
require_relative "../test/gem_manifest"
require_relative "release_smoke"

module PumaRelease
  PLATFORMS = %w[ruby java].freeze
  PLACEHOLDERS = ["TODO", "TBD", "FIXME", "PLACEHOLDER", "CODENAME", "???", "TO BE NAMED", "INSERT CODENAME HERE"].freeze

  class Notes < RubyGemRelease::Changelog::Notes
    def initialize
      super(path: "History.md", expand_references: true,
        heading: ->(value) { /^## #{Regexp.escape(value)} \/ \d{4}-\d{2}-\d{2}$/ })
    end

    def read(version)
      notes = super
      protected_lines = []
      Commonmarker.parse(notes).walk do |node|
        if [:code_block, :html_block].include?(node.type)
          position = node.source_position
          protected_lines.concat((position[:start_line]..position[:end_line]).to_a)
        elsif node.type == :text && node.string_content.match?(/\[#\d+\]/)
          raise "Missing release note link definition"
        end
      end
      notes.lines.each_with_index.reject { |line, index| !protected_lines.include?(index + 1) && line.match?(/^\[#\d+\]:/) }.map(&:first).join.strip
    end
  end

  extend Rake::DSL
  module_function

  def run(*command)
    output, error, status = Open3.capture3(*command)
    raise "#{command.first} failed: #{error}\n#{output}" unless status.success?

    output
  end

  def version
    Gem::Specification.load(File.expand_path("puma.gemspec")).version.to_s
  end

  def release
    selected = ENV.fetch("INPUT_VERSION", "")
    selected = version if selected.empty?
    raise "Expected MAJOR.MINOR.PATCH" unless /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)\z/.match?(selected)
    raise "Version must be prepared in the reviewed release PR" unless selected == version

    history = File.read("History.md")
    heading = history.match(/^## #{Regexp.escape(selected)} \/ (\d{4}-\d{2}-\d{2})$/)
    raise "Missing dated History.md section for #{selected}" unless heading

    notes = Notes.new.read(selected) if Gem.loaded_specs.key?("commonmarker")
    RubyGemRelease::Release.new(version: selected, gemspec_version: version, date: Date.iso8601(heading[1]), notes: notes)
  end

  def publication_job?
    ENV["GITHUB_ACTIONS"] == "true" && ENV["GITHUB_JOB"] == "publish"
  end

  def validate!(value, publishing: false)
    raise "Version changed" unless value.version == version
    raise "Release checkout must be clean" unless run("git", "status", "--porcelain").empty?

    codename = File.read("lib/puma/const.rb")[/CODE_NAME = "([^"]*)"/, 1]
    raise "Set the release codename" if codename.nil? || codename.strip.empty? || PLACEHOLDERS.include?(codename.upcase)
    return unless publishing

    raise "Publication requires the GitHub Actions publish job" unless publication_job?
    raise "Publication is restricted to puma/puma" unless ENV["GITHUB_REPOSITORY"] == "puma/puma"

    branch = ENV.fetch("GITHUB_REF", "").delete_prefix("refs/heads/")
    series = value.version.split(".").first(2).join("-")
    raise "Release from main or #{series}-stable" unless ["main", "#{series}-stable"].include?(branch)

    head = run("git", "rev-parse", "HEAD").strip
    validate_review!(value, branch, head)
  end

  def validate_review!(value, branch, head)
    number = ENV.fetch("RELEASE_PR", "")
    raise "Supply the reviewed release PR number" unless /\A[1-9]\d*\z/.match?(number)

    pr = JSON.parse(run("gh", "api", "repos/puma/puma/pulls/#{number}"))
    unless pr["merged"] && pr.dig("base", "ref") == branch &&
        pr.dig("head", "ref") == "release-v#{value.version}" && pr["merge_commit_sha"] == head
      raise "HEAD must be the merged release PR"
    end
    reviews = JSON.parse(run("gh", "api", "--paginate", "--slurp", "repos/puma/puma/pulls/#{number}/reviews")).flatten
    latest = reviews.reject { |review| review["state"] == "COMMENTED" }.group_by { |review| review.dig("user", "login") }.values.map(&:last)
    maintainers = %w[OWNER MEMBER COLLABORATOR]
    approved = latest.any? do |review|
      review["state"] == "APPROVED" && review.dig("user", "type") == "User" &&
        maintainers.include?(review["author_association"]) &&
        review.dig("user", "login") != pr.dig("user", "login") &&
        review["commit_id"] == pr.dig("head", "sha")
    end
    raise "Release PR needs a current human maintainer approval" unless approved

    checks = JSON.parse(run("gh", "pr", "checks", number, "--repo", "puma/puma", "--json", "name,state,workflow"))
    completed = %w[SUCCESS NEUTRAL SKIPPED]
    unless checks.any? { |check| check["workflow"] == "Tests" && check["state"] == "SUCCESS" } &&
        checks.all? { |check| completed.include?(check["state"]) }
      raise "Release PR checks must have passed"
    end
  end

  def build!(value, platform)
    raise "Unknown gem platform" unless PLATFORMS.include?(platform)
    spec_path = "puma.gemspec"
    if platform == "java"
      normalize_java!
      spec = Gem::Specification.load(File.expand_path(spec_path))
      spec.platform = Gem::Platform.new("java")
      spec.extensions = []
      spec.files = PumaGemManifest.shipped(tracked, platform: platform)
      FileUtils.mkdir_p("tmp")
      spec_path = "tmp/puma-release.gemspec"
      File.write(spec_path, spec.to_ruby)
    end
    RubyGemRelease::Package::RubyGem.new(gemspec: spec_path, directory: File.join("pkg/release", platform)).build!(value)
    verify!(value, platform)
  end

  def normalize_java!
    path = File.expand_path(PumaGemManifest::JAVA_EXTENSION)
    Dir.mktmpdir("puma-release-jar-") do |directory|
      Dir.chdir(directory) { run("jar", "--extract", "--file", path) }
      files = Dir.glob("**/*", base: directory).select { |file| File.file?(File.join(directory, file)) }.sort
      # JDK 17+ supports fixed ZIP timestamps; preserve the compiler's manifest.
      run("jar", "--create", "--file", path, "--no-manifest", "--date=1980-01-02T00:00:00Z",
        *files.flat_map { |file| ["-C", directory, file] })
    end
  end

  def tracked
    run("git", "ls-tree", "-r", "--name-only", "-z", "HEAD").split("\0")
  end

  def verify!(value, platform)
    raise "Unknown gem platform" unless PLATFORMS.include?(platform)

    audit = RubyGemRelease::Package::ContentAudit.new(expected_files: -> { PumaGemManifest.shipped(tracked, platform: platform) },
      generated: platform == "java" ? [PumaGemManifest::JAVA_EXTENSION] : [])
    package = RubyGemRelease::Package::Prebuilt.from_manifest(manifest: File.join("pkg/release", platform, "release.json"),
      name: "puma", version: value.version, platform: platform, audit: audit)
    path = package.artifact(value)
    spec = Gem::Package.new(path).spec

    extensions = platform == "ruby" ? ["ext/puma_http11/extconf.rb"] : []
    raise "Incorrect gem extensions" unless spec.extensions == extensions

    puts "#{Digest::SHA256.file(path).hexdigest}  #{File.basename(path)}"
    package
  end

  def smoke!(value, platform)
    PumaReleaseSmoke.call(verify!(value, platform).artifact(value))
  end

  def workflow(value = release, destination: RubyGemRelease::Destination::RubyGems.new, hosting: nil, provider: RubyGemRelease::ExecutionProvider.current)
    raise "Publish releases with CRuby and Commonmarker" unless RUBY_ENGINE == "ruby" && Gem.loaded_specs.key?("commonmarker")

    packages = RubyGemRelease::Package::Collection.new(packages: PLATFORMS.map { |platform| verify!(value, platform) })
    series = value.version.split(".").first(2).join("-")
    hosting ||= RubyGemRelease::Hosting::GitHubRelease.new(repository: "puma/puma",
      latest: ENV["GITHUB_REF"] == "refs/heads/main" ? nil : false)
    workflow = RubyGemRelease::Workflow::ReviewedRubyGem.new(package: packages, branches: ["main", "#{series}-stable"],
      notes: Notes.new, destination: destination, hosting: hosting, provider: provider,
      validate: ->(ctx) { validate!(ctx.release, publishing: true) })
    workflow.after(:capture) { |_ctx| provider.export("RELEASE_DATE" => value.date.iso8601) }
    [:authenticate, :build_package, :publish_registry, :publish_hosted_release].each do |stage|
      workflow.before(stage) { |ctx| validate!(ctx.release, publishing: true) }
    end
    workflow
  end

  def install_tasks
    if publication_job?
      workflow.install_tasks
      desc "Verify reviewed source and checkpoint the retained release archives"
      task "release:preflight" => %w[release:workflow:capture release:validate release:prepare release:workflow:resolve release:workflow:checkpoint]
    else
      RubyGemRelease::Tasks.install(destination: RubyGemRelease::Destination.new) do |tasks|
        tasks.validate { validate!(release) }
        tasks.publish { raise "Publication requires the GitHub Actions publish job" }
      end
      task "release:validate" => "release:context"
      task "release:publish" => "release:context"
    end
    namespace :release do
      task :context do
        value = release
        ENV["GEMSPEC_VERSION"] = value.gemspec_version
        ENV["RELEASE_VERSION"] = value.version
        ENV["RELEASE_DATE"] = value.date.iso8601
      end
      desc "Build and verify the current runtime's release gem"
      task :build => :validate
      task :build do
        build!(release, ENV.fetch("PUMA_RELEASE_PLATFORM", "ruby"))
      end
      desc "Verify both retained release gems"
      task :verify do
        PLATFORMS.each { |platform| verify!(release, platform) }
      end
      desc "Install and exercise the current runtime's release gem"
      task :smoke do
        smoke!(release, ENV.fetch("PUMA_RELEASE_PLATFORM", "ruby"))
      end
    end
  end
end
