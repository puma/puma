# frozen_string_literal: true

require 'yaml'

module Puma
  class StateFile
    def initialize
      @options = {}
    end

    def save(path, permission = nil)
      contents =YAML.dump @options
      if permission
        File.write path, contents, mode: 'wb:UTF-8'
      else
        File.write path, contents, mode: 'wb:UTF-8', perm: permission
      end
    end

    def load(path)
      @options = YAML.load File.read(path)
    end

    FIELDS = %w!control_url control_auth_token pid running_from!

    FIELDS.each do |f|
      define_method f do
        @options[f]
      end

      define_method "#{f}=" do |v|
        @options[f] = v
      end
    end
  end
end
