require 'rubocop'

module RuboCop
  module Cop
    module Puma
      class TestsMustUsePumaTest < Base
        extend AutoCorrector

        MSG = 'Inherit from PumaTest instead of Minitest::Test'

        def_node_matcher :inherits_from_minitest_test?, <<~PATTERN
          (class _ (const (const nil? :Minitest) :Test) ...)
        PATTERN

        def on_class(node)
          return unless inherits_from_minitest_test?(node)

          add_offense(node.children[1]) do |corrector|
            corrector.replace(node.children[1], 'PumaTest')
          end
        end
      end
    end
  end
end
