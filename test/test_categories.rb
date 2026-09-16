# frozen_string_literal: true

require_relative "helper"
require_relative "categories"

class TestCategories < PumaTest
  def test_integration_list_matches_classifier
    listed = PumaTestCategories.integration_basenames
    discovered = PumaTestCategories.discover_integration_basenames

    assert_equal discovered, listed,
      "Update INTEGRATION_TEST_FILES in test/categories.rb when adding or " \
      "removing TestIntegration / helpers/integration tests"
  end
end
