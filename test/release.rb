# frozen_string_literal: true

require_relative "helper"

require_relative "../tools/release" if Gem.loaded_specs.key?("ruby-gem-release")

class TestRelease < PumaTest
  def setup
    skip "Release tooling requires Ruby 3.3+" unless defined?(PumaRelease)
    @directory = Dir.mktmpdir("puma-release-test-")
    @previous = Dir.pwd
    @environment = ENV.to_h
    Dir.chdir(@directory)
    ENV.delete("INPUT_VERSION")
    ENV.delete("GITHUB_ACTIONS")
    ENV.delete("GITHUB_JOB")
    ENV["GITHUB_REF"] = ENV["SOURCE_REF"] = "refs/heads/main"
    ENV["RELEASE_DATA_DIR"] = File.expand_path("tmp/release-data")
    FileUtils.mkdir_p(ENV["RELEASE_DATA_DIR"])
    ENV["SOURCE_DATE_EPOCH"] = "315619200"
    write("lib/puma/const.rb", 'CODE_NAME = "Test Release"')
    write("lib/puma.rb", "# Puma fixture\n")
    write("README.md", "Puma fixture\n")
    write("ext/puma_http11/extconf.rb", "# Extension fixture\n")
    write("ext/puma_http11/http11_parser.c", "/* Parser fixture */\n")
    write("History.md", "## 1.2.3 / 2026-11-15\n\n* Fix a bug ([#123])\n\n[#123]:https://github.com/puma/puma/pull/123\n")
    write(".gitignore", "pkg/\ntmp/\nlib/puma/puma_http11.jar\n")
    write("puma.gemspec", <<~RUBY)
      Gem::Specification.new do |s|
        s.name = "puma"
        s.version = "1.2.3"
        s.summary = "Release fixture"
        s.authors = ["Puma"]
        s.files = #{PumaGemManifest::SHIPPED.inspect}.flat_map { |pattern| Dir.glob(pattern) }.select { |path| File.file?(path) }
        s.extensions = ["ext/puma_http11/extconf.rb"]
      end
    RUBY
    git("init", "-b", "main")
    git("config", "core.autocrlf", "false")
    git("config", "user.name", "Release Test")
    git("config", "user.email", "release@example.invalid")
    commit
    @release = PumaRelease.release
  end

  def teardown
    return unless @directory

    Process.kill("TERM", @gpg_agent_pid) if @gpg_agent_pid
    Dir.chdir(@previous)
    ENV.replace(@environment)
    FileUtils.remove_entry(@directory)
    FileUtils.remove_entry(@gnupg) if @gnupg
  end

  def test_commonmarker_is_limited_to_cruby_release_hosts
    {
      "x86_64-linux" => true,
      "arm64-darwin" => true,
      "x64-mingw-ucrt" => false,
      "x64-mswin64" => false,
      "aarch64-mingw-ucrt" => false,
      "amd64-freebsd14" => false
    }.each do |platform, supported|
      Object.stub_const(:RUBY_PLATFORM, platform) do
        gemfile = Bundler::Dsl.new
        gemfile.eval_gemfile(File.expand_path("../Gemfile", __dir__))
        dependencies = gemfile.dependencies.map(&:name)
        assert_includes dependencies, "ruby-gem-release"
        assert_equal supported && RUBY_ENGINE == "ruby", dependencies.include?("commonmarker")
      end
    end
  end

  def test_packaging_remains_available_without_commonmarker_but_publication_does_not
    specifications = Gem.loaded_specs.reject { |name, _| name == "commonmarker" }
    Gem.stub(:loaded_specs, specifications) do
      value = PumaRelease.release
      assert_nil value.notes
      PumaRelease.build!(value, "ruby")
      assert File.file?(PumaRelease.verify!(value, "ruby").artifact(value))
      assert_match(/CRuby and Commonmarker/, assert_raises(RuntimeError) { PumaRelease.workflow(value) }.message)
    end
  end

  def test_notes_expand_links_in_the_last_history_section
    skip_unless_notes
    assert_equal "* Fix a bug ([#123](<https://github.com/puma/puma/pull/123>))", @release.notes
    assert_equal Date.new(2026, 11, 15), @release.date
  end

  def test_notes_do_not_include_older_sections
    skip_unless_notes
    File.open("History.md", "a") { |file| file.puts "\n## 1.2.2 / 2026-11-14\n\n* Older notes\n" }
    refute_includes PumaRelease.release.notes, "Older notes"
  end

  def test_missing_link_definition_fails
    skip_unless_notes
    write("History.md", "## 1.2.3 / 2026-11-15\n\n* Fix ([#456])\n")
    assert_raises(RuntimeError) { PumaRelease.release }
  end

  def test_empty_notes_fail
    skip_unless_notes
    write("History.md", "## 1.2.3 / 2026-11-15\n")
    assert_raises(ArgumentError) { PumaRelease.release }
  end

  def test_notes_preserve_code_and_subheadings_without_changing_history
    skip_unless_notes
    history = <<~MARKDOWN
      ## 1.2.3 / 2026-11-15

      ### Bugfixes

      * Fix a bug ([#123])

      ```markdown
      ## 1.2.3 / 2000-01-01
      [#456]:https://example.invalid/code
      [#456]
      ```

      ## 1.2.2 / 2026-11-14

      * Older notes

      [#123]:https://github.com/puma/puma/pull/123
    MARKDOWN
    write("History.md", history)
    notes = PumaRelease.release.notes
    assert_includes notes, "### Bugfixes"
    assert_includes notes, "[#123](<https://github.com/puma/puma/pull/123>)"
    assert_includes notes, "[#456]:https://example.invalid/code\n[#456]"
    refute_includes notes, "Older notes"
    assert_equal history, File.read("History.md")
  end

  def test_duplicate_release_headings_fail
    skip_unless_notes
    File.open("History.md", "a") { |file| file.puts "\n## 1.2.3 / 2026-11-16\n\n* Duplicate\n" }
    assert_raises(ArgumentError) { PumaRelease.release }
  end

  def test_invalid_date_fails
    write("History.md", "## 1.2.3 / 2026-02-31\n\n* Fix\n")
    assert_raises(Date::Error) { PumaRelease.release }
  end

  def test_version_overrides_cannot_bypass_reviewed_version
    ENV["INPUT_VERSION"] = "1.2.4"
    assert_raises(RuntimeError) { PumaRelease.release }
    ENV["INPUT_VERSION"] = "01.2.3"
    assert_raises(RuntimeError) { PumaRelease.release }
  end

  def test_clean_checkout_and_real_codename_are_required
    assert_nil PumaRelease.validate!(@release)
    write("lib/puma/const.rb", 'CODE_NAME = "INSERT CODENAME HERE"')
    assert_raises(RuntimeError) { PumaRelease.validate!(@release) }
    commit
    assert_raises(RuntimeError) { PumaRelease.validate!(@release) }
  end

  def test_publish_is_disabled_outside_the_publish_job_and_on_forks
    ENV["GITHUB_REPOSITORY"] = "puma/puma"
    assert_match(/GitHub Actions publish job/, assert_raises(RuntimeError) { PumaRelease.validate!(@release, publishing: true) }.message)
    ENV["GITHUB_JOB"] = "publish"
    assert_match(/GitHub Actions publish job/, assert_raises(RuntimeError) { PumaRelease.validate!(@release, publishing: true) }.message)
    enter_publish_job
    ENV["GITHUB_JOB"] = "package"
    assert_match(/GitHub Actions publish job/, assert_raises(RuntimeError) { PumaRelease.validate!(@release, publishing: true) }.message)
    ENV["GITHUB_JOB"] = "publish"
    ENV["GITHUB_REPOSITORY"] = "dblock/puma"
    assert_match(/restricted to puma\/puma/, assert_raises(RuntimeError) { PumaRelease.validate!(@release, publishing: true) }.message)
  end

  def test_local_tasks_validate_without_loading_archives_and_refuse_publication
    PumaRelease.stub(:workflow, -> { flunk "Local tasks must not load publishing archives" }) do
      with_tasks(PumaRelease) do
        Rake::Task["release:validate"].invoke
        assert_match(/GitHub Actions publish job/, assert_raises(RuntimeError) { Rake::Task["release:publish"].invoke }.message)
      end
    end
  end

  def test_rejects_wrong_stable_series_and_unsigned_tags
    enter_publish_job
    ENV["GITHUB_REF"] = "refs/heads/1-1-stable"
    assert_raises(RuntimeError) { PumaRelease.validate!(@release, publishing: true) }
    ENV["GITHUB_REF"] = "refs/heads/1-2-stable"
    git("tag", "v1.2.3")
    create_remote
    source = RubyGemRelease::SourceControl::ReviewedGit.new(branch: "main", branches: ["main"], directory: ENV["RELEASE_DATA_DIR"])
    assert_match(/cannot verify/, assert_raises(RuntimeError) { source.verify!(@release) }.message)
  end

  def test_build_verifies_exact_files_and_is_reproducible
    PumaRelease.build!(@release, "ruby")
    path = PumaRelease.verify!(@release, "ruby").artifact(@release)
    checksum = Digest::SHA256.file(path).hexdigest
    PumaRelease.build!(@release, "ruby")
    assert_equal checksum, Digest::SHA256.file(path).hexdigest
  end

  def test_signed_tag_and_remote_branch_are_verified_without_remote_publication
    skip_unless_notes
    skip "Signed-source integration requires Unix GPG (covered by release CI)" if Gem.win_platform?
    begin
      PumaRelease.run("gpg", "--version")
      PumaRelease.run("gpg-connect-agent", "--version")
    rescue Errno::ENOENT
      skip "Signed-source integration requires GPG (covered by release CI)"
    end
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    enter_publish_job
    ENV["GITHUB_REF"] = "refs/heads/main"
    @gnupg = Dir.mktmpdir("puma-gpg-", "/tmp")
    ENV["GNUPGHOME"] = @gnupg
    PumaRelease.run("gpg", "--batch", "--pinentry-mode", "loopback", "--passphrase", "",
      "--quick-generate-key", "Release Test <release@example.invalid>", "ed25519", "sign", "0")
    @gpg_agent_pid = Integer(PumaRelease.run("gpg-connect-agent", "GETINFO pid", "/bye")[/^D (\d+)/, 1], 10)
    git("-c", "user.signingkey=release@example.invalid", "tag", "-s", "v1.2.3", "-m", "Release fixture")
    create_remote
    head = git("rev-parse", "HEAD")
    tags = git("ls-remote", "--tags", "origin")
    destination = RubyGemRelease::Destination.new
    destination.define_singleton_method(:published?) { |*_, **| false }
    destination.define_singleton_method(:publish!) { |_value, package:| package.artifacts(_value) }
    hosted = []
    hosting = Object.new
    hosting.define_singleton_method(:publish!) { |value, package:| hosted << [value.notes, package.artifacts(value)] }
    workflow = PumaRelease.workflow(@release, destination: destination, hosting: hosting)
    PumaRelease.stub(:validate_review!, nil) do
      PumaRelease.stub(:workflow, workflow) do
        with_tasks(PumaRelease) do
          stages = %w[release:workflow:capture release:validate release:prepare release:workflow:resolve release:workflow:checkpoint]
          completed = []
          stages.each { |stage| Rake::Task[stage].enhance { completed << stage } }
          Rake::Task["release:preflight"].invoke
          assert_equal stages, completed
          assert_empty hosted
          assert File.file?(File.join(ENV["RELEASE_DATA_DIR"], "release.bundle"))
          %w[release:publish release:bump].each do |task|
            Rake::Task[task].invoke
          end
        end
      end
      assert_equal @release.date.iso8601, ENV["RELEASE_DATE"]
      assert_equal @release.notes, hosted.first.first
      assert_equal %w[puma-1.2.3.gem puma-1.2.3-java.gem], hosted.first.last.map { |path| File.basename(path) }
      assert_equal head, git("rev-parse", "HEAD")
      assert_equal tags, git("ls-remote", "--tags", "origin")
      write("README.md", "A later commit\n")
      commit
      git("push", "origin", "main")
      git("switch", "--detach", "v1.2.3")
      assert_match(/branch advanced/, assert_raises(RuntimeError) { workflow.git.verify!(@release) }.message)
    end
  end

  def test_checksum_guard_rejects_tampered_archives
    package = build_package("ruby")
    File.open(package.artifact(@release), "ab") { |file| file.write("tampered") }
    assert_raises(RuntimeError) { PumaRelease.verify!(@release, "ruby") }
  end

  def test_manifest_rejects_developer_files_and_missing_files
    %w[extra missing].each do |variant|
      build_package("ruby") do |spec|
        if variant == "extra"
          spec.files << "puma.gemspec"
        else
          spec.files.delete("README.md")
        end
      end
      assert_match(/file list/, assert_raises(RuntimeError) { PumaRelease.verify!(@release, "ruby") }.message)
    end
  end

  def test_source_comparison_rejects_modified_packaged_files
    write("lib/puma.rb", "# Not the reviewed source\n")
    build_package("ruby")
    assert_match(/bytes differ from Git source/, assert_raises(RuntimeError) { PumaRelease.verify!(@release, "ruby") }.message)
  end

  def test_java_package_has_a_distinct_name_and_no_c_sources
    package = build_package("java")
    path = package.artifact(@release)
    assert_equal "puma-1.2.3-java.gem", File.basename(path)
    assert_equal "java", Gem::Package.new(path).spec.platform.to_s
    assert_instance_of RubyGemRelease::Package::Prebuilt, PumaRelease.verify!(@release, "java")
  end

  def test_java_archive_normalization_is_reproducible
    skip "Requires JDK 17+ (covered by the Java package job)" unless ENV["PUMA_RELEASE_PLATFORM"] == "java"
    write("tmp/jar-source/Example.class", "Java bytecode fixture")
    path = File.expand_path(PumaGemManifest::JAVA_EXTENSION)
    PumaRelease.run("jar", "--create", "--file", path, "-C", "tmp/jar-source", ".")
    PumaRelease.normalize_java!
    checksum = Digest::SHA256.file(path).hexdigest
    File.utime(Time.now + 60, Time.now + 60, "tmp/jar-source/Example.class")
    PumaRelease.run("jar", "--create", "--file", path, "-C", "tmp/jar-source", ".")
    PumaRelease.normalize_java!
    assert_equal checksum, Digest::SHA256.file(path).hexdigest
  end

  def test_wrong_platform_is_rejected_even_with_a_valid_checksum
    package = build_package("ruby")
    FileUtils.mkdir_p("pkg/release/java")
    FileUtils.cp(Dir[File.join(package.directory, "release.*")], "pkg/release/java")
    assert_match(/metadata/, assert_raises(RuntimeError) { PumaRelease.verify!(@release, "java") }.message)
  end

  def test_archive_consumer_rejects_wrong_platform_before_installation
    package = build_package(RUBY_ENGINE == "jruby" ? "ruby" : "java")
    assert_match(/consumer runtime/, assert_raises(RuntimeError) { PumaReleaseSmoke.call(package.artifact(@release)) }.message)
  end

  def test_unset_and_empty_consumer_paths_require_one_archive
    [nil, ""].each do |path|
      assert_match(/exactly one/, assert_raises(RuntimeError) { PumaReleaseSmoke.call(path) }.message)
    end
  end

  def test_consumer_preserves_selected_bundle_dependencies_when_unbundling
    package = build_package(RUBY_ENGINE == "jruby" ? "java" : "ruby")
    path = package.artifact(@release)
    unbundled = false
    paths = -> { unbundled ? ["/system/gems"] : ["/selected/bundle"] }
    without_bundle = ->(&block) { unbundled = true; block.call }
    command = lambda do |*args|
      assert_includes args.first.fetch("GEM_PATH").split(File::PATH_SEPARATOR), "/selected/bundle" if args.first.is_a?(Hash)
      ""
    end
    Gem.stub(:path, paths) do
      Bundler.stub(:with_unbundled_env, without_bundle) do
        PumaReleaseSmoke.stub(:run, command) { PumaReleaseSmoke.call(path) }
      end
    end
  end

  def test_registry_lookup_is_platform_specific_and_checks_identity
    package = build_package("java")
    path = package.artifact(@release)
    requested = nil
    metadata = { "version" => "1.2.3", "platform" => "java", "sha" => Digest::SHA256.file(path).hexdigest }
    http = Object.new
    http.define_singleton_method(:get) do |uri|
      requested = uri
      Struct.new(:code, :body).new("200", JSON.generate(metadata))
    end
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
      assert RubyGemRelease::Destination::RubyGems.new.published?(@release, package: package)
      assert_includes requested, "platform=java"
      metadata["sha"] = "wrong"
      assert_raises(RuntimeError) { RubyGemRelease::Destination::RubyGems.new.published?(@release, package: package) }
    end
  end

  def test_registry_absence_errors_and_checksum_conflicts
    package = build_package("ruby")
    response = Struct.new(:code, :body).new("404", "")
    http = Object.new
    http.define_singleton_method(:get) { |_uri| response }
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
      refute RubyGemRelease::Destination::RubyGems.new.published?(@release, package: package)
      response.code = "503"
      assert_raises(RuntimeError) { RubyGemRelease::Destination::RubyGems.new.published?(@release, package: package) }
      response.code = "200"
      response.body = JSON.generate("version" => "1.2.3", "platform" => "ruby", "sha" => "wrong")
      assert_raises(RuntimeError) { RubyGemRelease::Destination::RubyGems.new.published?(@release, package: package) }
    end
  end

  def test_an_accepted_upload_with_a_lost_response_is_not_republished
    package = build_package("java")
    checksum = Digest::SHA256.file(package.artifact(@release)).hexdigest
    requests = 0
    http = Object.new
    http.define_singleton_method(:get) do |_uri|
      requests += 1
      if requests == 1
        Struct.new(:code, :body).new("404", "")
      else
        Struct.new(:code, :body).new("200", JSON.generate("version" => "1.2.3", "platform" => "java", "sha" => checksum))
      end
    end
    failed = Object.new
    failed.define_singleton_method(:success?) { false }
    uploads = 0
    capture = Open3.method(:capture3)
    command = lambda do |*args|
      next capture.call(*args) if args.first == "git"
      assert_includes args, "push"
      uploads += 1
      ["", "Response lost", failed]
    end
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
      Open3.stub(:capture3, command) do
        RubyGemRelease::Destination::RubyGems.new.publish!(@release, package: package)
      end
    end
    assert_equal 1, uploads
    assert_equal 2, requests
  end

  def test_review_requires_a_merged_matching_pr_and_current_human_approval
    ENV["RELEASE_PR"] = "123"
    pr = {
      "merged" => true, "base" => { "ref" => "main" }, "head" => { "ref" => "release-v1.2.3", "sha" => "reviewed" },
      "merge_commit_sha" => "released", "user" => { "login" => "author" }
    }
    review = {
      "state" => "APPROVED", "user" => { "login" => "maintainer", "type" => "User" },
      "author_association" => "MEMBER", "commit_id" => "reviewed"
    }
    checks = [{ "workflow" => "Tests", "state" => "SUCCESS" }]
    command = lambda do |*args|
      if args.include?("checks")
        JSON.generate(checks)
      elsif args.last.end_with?("/reviews")
        JSON.generate([[review]])
      else
        JSON.generate(pr)
      end
    end
    PumaRelease.stub(:run, command) do
      assert_nil PumaRelease.validate_review!(@release, "main", "released")
      review["commit_id"] = "stale"
      assert_raises(RuntimeError) { PumaRelease.validate_review!(@release, "main", "released") }
      review["commit_id"] = "reviewed"
      review["user"]["type"] = "Bot"
      assert_raises(RuntimeError) { PumaRelease.validate_review!(@release, "main", "released") }
      review["user"]["type"] = "User"
      checks.first["state"] = "FAILURE"
      assert_raises(RuntimeError) { PumaRelease.validate_review!(@release, "main", "released") }
      checks.first["state"] = "SUCCESS"
      pr["merged"] = false
      assert_raises(RuntimeError) { PumaRelease.validate_review!(@release, "main", "released") }
    end
  end

  def test_publication_checks_both_platforms_before_uploading_and_is_repeatable
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    events = []
    present = {}
    http = Object.new
    http.define_singleton_method(:get) do |uri|
      platform = URI.decode_www_form(URI(uri).query).to_h.fetch("platform")
      events << [:check, platform]
      if present[platform]
        Struct.new(:code, :body).new("200", JSON.generate("sha" => present.fetch(platform)))
      else
        Struct.new(:code, :body).new("404", "")
      end
    end
    destination = RubyGemRelease::Destination::RubyGems.new
    destination.define_singleton_method(:authenticate!) { |provider:| events << :authenticate }
    capture = Open3.method(:capture3)
    command = lambda do |*args|
      next capture.call(*args) if args.first == "git"
      assert_includes args, "push"
      path = args.last
      platform = Gem::Package.new(path).spec.platform.to_s
      events << [:upload, platform]
      present[platform] = Digest::SHA256.file(path).hexdigest
      ["Accepted", "", Struct.new(:success?).new(true)]
    end
    hosting = Object.new
    hosting.define_singleton_method(:publish!) { |value, package:| events << [:host, package.artifacts(value).map { |path| File.basename(path) }] }
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
      Open3.stub(:capture3, command) do
        PumaRelease.stub(:validate!, nil) do
          publish(destination: destination, hosting: hosting)
          assert_equal [[:check, "ruby"], [:check, "java"], :authenticate], events.first(3)
          assert_equal [[:upload, "ruby"], [:upload, "java"]], events.select { |event| event.is_a?(Array) && event.first == :upload }
          assert_equal [:host, %w[puma-1.2.3.gem puma-1.2.3-java.gem]], events.last
          events.clear
          publish(destination: destination, hosting: hosting)
          refute_includes events, :authenticate
          refute events.any? { |event| event.is_a?(Array) && event.first == :upload }
          assert_equal :host, events.last.first
        end
      end
    end
  end

  def test_failed_publication_does_not_create_hosted_release
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    destination = Object.new
    destination.define_singleton_method(:published?) { |*_args, **_kwargs| false }
    destination.define_singleton_method(:authenticate!) { |provider:| nil }
    destination.define_singleton_method(:publish!) { |*_args, **_kwargs| raise "Upload failed" }
    hosting = Object.new
    hosting.define_singleton_method(:publish!) { |*_args, **_kwargs| flunk "Must not host a failed publication" }
    PumaRelease.stub(:validate!, nil) do
      assert_match(/Upload failed/, assert_raises(RuntimeError) { publish(destination: destination, hosting: hosting) }.message)
    end
  end

  def test_a_conflict_on_the_second_platform_prevents_all_publication
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    calls = 0
    http = Object.new
    http.define_singleton_method(:get) do |_uri|
      calls += 1
      Struct.new(:code, :body).new(calls == 2 ? "200" : "404", JSON.generate("sha" => "conflict"))
    end
    destination = RubyGemRelease::Destination::RubyGems.new
    destination.define_singleton_method(:authenticate!) { |**| flunk "Must preflight both platforms before authentication" }
    Net::HTTP.stub(:start, ->(*_args, **_kwargs, &block) { block.call(http) }) do
      assert_match(/checksum differs/, assert_raises(RuntimeError) { publish(destination: destination) }.message)
    end
    assert_equal 2, calls
  end

  def test_a_tampered_second_archive_prevents_registry_queries
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    Net::HTTP.stub(:start, ->(*) { flunk "Must verify both local archives before querying RubyGems" }) do
      assert_match(/artifact changed/, assert_raises(RuntimeError) do
        publish do |workflow|
          path = workflow.package.packages.last.artifact(@release)
          File.open(path, "ab") { |file| file.write("tampered") }
        end
      end.message)
    end
  end

  def test_approval_is_rechecked_after_uploads_before_hosting
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    enter_publish_job
    uploaded = false
    reviewed = 0
    destination = RubyGemRelease::Destination.new
    destination.define_singleton_method(:published?) { |*_, **| false }
    destination.define_singleton_method(:publish!) { |*_, **| uploaded = true }
    review = lambda do |*|
      reviewed += 1
      raise "Approval changed" if uploaded
    end
    hosting = Object.new
    hosting.define_singleton_method(:publish!) { |*_, **| flunk "Must recheck approval before hosting" }
    PumaRelease.stub(:validate_review!, review) do
      assert_match(/Approval changed/, assert_raises(RuntimeError) { publish(destination: destination, hosting: hosting) }.message)
    end
    assert uploaded
    assert_operator reviewed, :>=, 4
  end

  def test_maintenance_release_is_never_transiently_marked_latest
    skip_unless_notes
    PumaRelease::PLATFORMS.each { |platform| build_package(platform) }
    api = Object.new
    api.define_singleton_method(:get) { |*| nil }
    destination = RubyGemRelease::Destination.new
    destination.define_singleton_method(:published?) { |*_, **| false }
    destination.define_singleton_method(:publish!) { |*_, **| nil }
    commands = []
    capture = Open3.method(:capture3)
    command = lambda do |*args|
      next capture.call(*args) unless args.first == "gh"
      commands << args
      assert_equal @release.notes, File.read(args[args.index("--notes-file") + 1])
      ["https://example.invalid/release", "", Struct.new(:success?).new(true)]
    end
    RubyGemRelease::GitHubAPI.stub(:new, api) do
      Open3.stub(:capture3, command) do
        PumaRelease.stub(:validate!, nil) do
          ENV["GITHUB_REF"] = "refs/heads/1-2-stable"
          publish(destination: destination)
          assert_includes commands.first, "--latest=false"
          assert_equal ["create"], commands.map { |args| args[2] }
          ENV["GITHUB_REF"] = "refs/heads/main"
          publish(destination: destination)
          refute commands.last.any? { |argument| argument.start_with?("--latest=") }
        end
      end
    end
  end

  private

  def enter_publish_job
    ENV["GITHUB_ACTIONS"] = "true"
    ENV["GITHUB_JOB"] = "publish"
    ENV["GITHUB_REPOSITORY"] = "puma/puma"
    ENV["RUNNER_TEMP"] = ENV.fetch("RELEASE_DATA_DIR")
    ENV["GITHUB_ENV"] = File.join(ENV["RUNNER_TEMP"], "github-env")
  end

  def skip_unless_notes
    skip "Markdown notes and publication require Commonmarker" unless Gem.loaded_specs.key?("commonmarker")
  end

  def create_remote
    git("init", "--bare", "tmp/remote.git")
    git("remote", "add", "origin", File.join(@directory, "tmp/remote.git"))
    git("push", "origin", "main", "refs/tags/v1.2.3")
  end

  def with_tasks(workflow)
    previous = Rake.application
    Rake.application = Rake::Application.new
    workflow.install_tasks
    yield
  ensure
    Rake.application = previous
  end

  def publish(destination: RubyGemRelease::Destination::RubyGems.new, hosting: nil)
    ENV["GEMSPEC_VERSION"] = ENV["RELEASE_VERSION"] = @release.version
    ENV["RELEASE_DATE"] = @release.date.iso8601
    ENV["SOURCE_COMMIT"] = git("rev-parse", "HEAD").strip
    workflow = PumaRelease.workflow(@release, destination: destination, hosting: hosting)
    yield workflow if block_given?
    workflow.git.stub(:verify!, ENV["SOURCE_COMMIT"]) do
      workflow.git.stub(:preserve!, nil) do
        with_tasks(workflow) { Rake::Task["release:publish"].invoke }
      end
    end
  end

  def write(path, content)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, content)
  end

  def git(*args)
    PumaRelease.run("git", *args)
  end

  def commit
    git("add", ".")
    git("-c", "commit.gpgsign=false", "commit", "-m", "Release fixture")
  end

  def build_package(platform)
    write("lib/puma/puma_http11.jar", "Java archive fixture") if platform == "java"
    spec = Gem::Specification.load(File.expand_path("puma.gemspec")).dup
    spec.platform = platform
    spec.files = PumaGemManifest.shipped(PumaRelease.tracked, platform: platform)
    spec.extensions = [] if platform == "java"
    yield spec if block_given?
    @build_index = (@build_index || 0) + 1
    path = File.expand_path("tmp/fixture-#{@build_index}.gemspec")
    write(path, spec.to_ruby)
    package = RubyGemRelease::Package::RubyGem.new(gemspec: path, directory: File.join("pkg/release", platform))
    package.build!(@release)
    package
  end
end
