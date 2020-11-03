# frozen_string_literal: true

module Puma
  module JSON
    class SerializationError < StandardError; end

    class << self
      def generate(value)
        case value
        when Array, Hash
          parts = []
          serialize_value parts, value
          parts.join ''
        else
          raise SerializationError, "Could not serialize object of type #{value.class}"
        end
      end

      private

      def serialize_value(output, value)
        case value
        when Array
          output << '['
          value.each_with_index do |member, index|
            output << ',' if index != 0
            serialize_value output, member
          end
          output << ']'
        when Hash
          output << '{'
          value.each_with_index do |(k, v), index|
            output << ',' if index != 0
            serialize_object_key output, k
            output << ':'
            serialize_value output, v
          end
          output << '}'
        when String
          serialize_string output, value
        when Integer
          output << value.to_s
        end
      end

      def serialize_string(output, value)
        output << '"'
        output << value.gsub(/[\\"]/, '\\' => '\\\\', '"' => '\\"')
        output << '"'
      end

      def serialize_object_key(output, value)
        case value
        when Symbol
          serialize_string output, value.to_s
        when String
          serialize_string output, value
        else
          raise SerializationError, "Could not serialize object of type #{value.class} as object key"
        end
      end
    end
  end
end
