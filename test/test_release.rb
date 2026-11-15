# frozen_string_literal: true

require_relative "helper"
require "open3"

class TestRelease < PumaTest
  def test_release_workflow
    skip "Release tooling requires Ruby 3.3+" unless Gem.loaded_specs.key?("ruby-gem-release")

    output, status = Open3.capture2e(Gem.ruby, "-rbundler/setup", "-I", File.expand_path("../lib", __dir__), "-I", __dir__,
      File.join(__dir__, "release.rb"), chdir: File.expand_path("..", __dir__))
    assert status.success?, output
  end
end
