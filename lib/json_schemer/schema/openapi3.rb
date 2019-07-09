# frozen_string_literal: true

module JSONSchemer
  module Schema
    class OpenApi3 < Draft4
      def validate_type(instance, type, &block)
        return if instance.schema['nullable'] && instance.data.nil?
        super
      end
    end
  end
end
