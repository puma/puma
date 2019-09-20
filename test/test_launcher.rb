require_relative "helper"

require "puma/configuration"

class TestLauncher < Minitest::Test
  def test_dependencies_and_files_to_require_after_prune_is_correctly_built_for_no_extra_deps
    skip_on :no_bundler

    deps, dirs = launcher.send(:dependencies_and_files_to_require_after_prune)

    assert_equal(1, deps.length)
    assert_match(%r{^nio4r:[\d.]+$}, deps.first)
    assert_equal(2, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
    refute_match(%r{gems/rdoc-[\d.]+/lib$}, dirs[2])
  end

  def test_dependencies_and_files_to_require_after_prune_is_correctly_built_with_extra_deps
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end

    deps, dirs = launcher(conf).send(:dependencies_and_files_to_require_after_prune)

    assert_equal(1, deps.length)
    assert_match(%r{^nio4r:[\d.]+$}, deps.first)
    assert_equal(3, dirs.length)
    assert_match(%r{puma/lib$}, dirs[0]) # lib dir
    assert_match(%r{puma-#{Puma::Const::PUMA_VERSION}$}, dirs[1]) # native extension dir
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dirs[2]) # rdoc dir
  end

  def test_extra_runtime_deps_directories_is_empty_for_no_config
    assert_equal([], launcher.send(:extra_runtime_deps_directories))
  end

  def test_extra_runtime_deps_directories_is_correctly_built
    skip_on :no_bundler
    conf = Puma::Configuration.new do |c|
      c.extra_runtime_dependencies ['rdoc']
    end
    dep_dirs = launcher(conf).send(:extra_runtime_deps_directories)

    assert_equal(1, dep_dirs.length)
    assert_match(%r{gems/rdoc-[\d.]+/lib$}, dep_dirs.first)
  end

  def test_puma_wild_location_is_an_absolute_path
    skip_on :no_bundler
    puma_wild_location = launcher.send(:puma_wild_location)

    assert_match(%r{bin/puma-wild$}, puma_wild_location)
    # assert no "/../" in path
    refute_match(%r{/\.\./}, puma_wild_location)
  end

  def test_prints_thread_traces
    launcher.send(:log_thread_status)
    events.stdout.rewind

    assert_match "Thread TID", events.stdout.read
  end

  def test_pid_file
    tmp_file = Tempfile.new("puma-test")
    tmp_path = tmp_file.path
    tmp_file.close!

    conf = Puma::Configuration.new do |c|
      c.pidfile tmp_path
    end

    launcher(conf).write_state

    assert_equal File.read(tmp_path).strip.to_i, Process.pid

    File.unlink tmp_path
  end

  private

  def events
    @events ||= Puma::Events.strings
  end

  def launcher(config = Puma::Configuration.new, evts = events)
    @launcher ||= Puma::Launcher.new(config, events: evts)
  end
end
