# frozen_string_literal: true

# Shared classification for rake test:unit / test:integration and test/runner.
#
# Litmus: integration tests spawn a Puma (or rackup) process and drive it from
# the outside (TestIntegration / helpers/integration). Unit tests call Puma
# in-process, including in-process servers that bind a port.
#
# Keep this file named without a test_*.rb prefix so the default suite glob
# does not load it as a test. test/test_categories.rb guards the list against
# drift from the classifier below.
module PumaTestCategories
  INTEGRATION_TEST_FILES = %w[
    test_http11.rb
    test_integration_cluster.rb
    test_integration_pumactl.rb
    test_integration_single.rb
    test_integration_ssl.rb
    test_integration_ssl_session.rb
    test_plugin.rb
    test_plugin_systemd.rb
    test_plugin_systemd_jruby.rb
    test_preserve_bundler_env.rb
    test_redirect_io.rb
    test_skip_sigusr2.rb
    test_skip_systemd.rb
    test_url_map.rb
    test_web_concurrency_auto.rb
    test_worker_gem_independence.rb
  ].freeze

  module_function

  def all_test_basenames(base = File.dirname(__FILE__))
    Dir[File.join(base, "test_*.rb")].map { |path| File.basename(path) }.sort
  end

  # Files that use the process-spawn integration helper. Used to detect list drift.
  def discover_integration_basenames(base = File.dirname(__FILE__))
    Dir[File.join(base, "test_*.rb")].sort.filter_map do |path|
      File.basename(path) if integration_source?(path)
    end
  end

  def integration_source?(path)
    source = File.read(path)
    source.match?(/require_relative\s+["']helpers\/integration["']/) ||
      source.match?(/<\s*TestIntegration\b/)
  end

  def integration_basenames
    INTEGRATION_TEST_FILES
  end

  def unit_basenames(base = File.dirname(__FILE__))
    all_test_basenames(base) - INTEGRATION_TEST_FILES
  end

  def integration_paths(base = File.dirname(__FILE__))
    INTEGRATION_TEST_FILES.map { |name| File.join(base, name) }
  end

  def unit_paths(base = File.dirname(__FILE__))
    unit_basenames(base).map { |name| File.join(base, name) }
  end
end
