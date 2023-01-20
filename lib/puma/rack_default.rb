# frozen_string_literal: true

require_relative '../rack/handler/puma'

if Object.const_defined? :Rackup
  module Rackup
    module Handler
      def self.default(options = {})
        ::Rackup::Handler::Puma
      end
    end
  end
else
  module Rack
    module Handler
      def self.default(options = {})
        ::Rack::Handler::Puma
      end
    end
  end
end
