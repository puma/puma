# frozen_string_literal: true

require_relative '../rack/handler/puma'

module Rack::Handler
  def self.default(options = {})
    Rack::Handler::Puma
  end
end
