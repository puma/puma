require_relative "helper"

require "puma/configuration"

class TestLauncher < Minitest::Test
  def test_dependencies_and_files_to_require_after_prune_is_correctly_built_for_no_extra_deps
    skip_on :no_bundler
    l = Puma::Launcher.new Puma::Configuration.new
    deps, dirs = l.send(:dependencies_and_files_to_require_after_prune)

    assert_equal(1, deps.length)
    assert_match(%r{^nio4r:[\d.]+$}, deps.first)
    assert_equal(2, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
  end

  def test_dependencies_and_files_to_require_after_prune_is_correctly_built_with_extra_deps
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end
    l = Puma::Launcher.new conf
    deps, dirs = l.send(:dependencies_and_files_to_require_after_prune)

    assert_equal(1, deps.length)
    assert_match(%r{^nio4r:[\d.]+$}, deps.first)
    assert_equal(3, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dirs[2]) # rdoc dir
  end

  def test_extra_runtime_deps_directories_is_empty_for_no_config
    l = Puma::Launcher.new Puma::Configuration.new
    assert_equal([], l.send(:extra_runtime_deps_directories))
  end

  def test_extra_runtime_deps_directories_is_correctly_built
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end
    l = Puma::Launcher.new conf
    dep_dirs = l.send(:extra_runtime_deps_directories)

    assert_equal(1, dep_dirs.length)
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dep_dirs.first)
  end

  def test_puma_wild_location_is_an_absolute_path
    skip_on :no_bundler
    l = Puma::Launcher.new Puma::Configuration.new
    puma_wild_location = l.send(:puma_wild_location)
    assert_match(%r{bin/puma-wild$}, puma_wild_location)
    # assert no "/../" in path
    refute_match(%r{/\.\./}, puma_wild_location)
  end

  def test_prints_thread_traces
    events = Puma::Events.strings
    l = Puma::Launcher.new(Puma::Configuration.new, events: events)

    l.send(:log_thread_status)
    events.stdout.rewind

    assert_match "Thread TID", events.stdout.read
  end
end
