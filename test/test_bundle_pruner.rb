# frozen_string_literal: true

require_relative 'helper'

class TestBundlePruner < Minitest::Test

  PUMA_VERS = "puma-#{Puma::Const::PUMA_VERSION}"

  def test_paths_to_require_after_prune_is_correctly_built_for_no_extra_deps
    skip_if :no_bundler

    dirs = bundle_pruner.send(:paths_to_require_after_prune)

    assert_equal(2, dirs.length)
    assert_equal(File.join(PROJECT_ROOT, "lib"), dirs[0]) # lib dir
    assert_operator dirs[1], :end_with?, PUMA_VERS # native extension dir
    refute_match(%r{gems/minitest-[\d.]+/lib$}, dirs[2])
  end

  def test_paths_to_require_after_prune_is_correctly_built_with_extra_deps
    skip_if :no_bundler

    dirs = bundle_pruner([], ['minitest']).send(:paths_to_require_after_prune)

    assert_equal(3, dirs.length)
    assert_equal(File.join(PROJECT_ROOT, "lib"), dirs[0]) # lib dir
    assert_operator dirs[1], :end_with?, PUMA_VERS # native extension dir
    assert_match(%r{gems/minitest-[\d.]+/lib$}, dirs[2]) # minitest dir
  end

  def test_extra_runtime_deps_paths_is_empty_for_no_config
    assert_equal([], bundle_pruner.send(:extra_runtime_deps_paths))
  end

  def test_extra_runtime_deps_paths_is_correctly_built
    skip_if :no_bundler

    dep_dirs = bundle_pruner([], ['minitest']).send(:extra_runtime_deps_paths)

    assert_equal(1, dep_dirs.length)
    assert_match(%r{gems/minitest-[\d.]+/lib$}, dep_dirs.first)
  end

  def test_puma_wild_path_is_an_absolute_path
    skip_if :no_bundler
    puma_wild_path = bundle_pruner.send(:puma_wild_path)

    assert_match(%r{bin/puma-wild$}, puma_wild_path)
    # assert no "/../" in path
    refute_match(%r{/\.\./}, puma_wild_path)
  end

  private

  def bundle_pruner(original_argv = nil, extra_runtime_dependencies = nil)
    @bundle_pruner ||= Puma::Launcher::BundlePruner.new(original_argv, extra_runtime_dependencies, Puma::LogWriter.null)
  end
end
