# frozen_string_literal: true

module JSONSchemer
  module Schema
    class Draft4 < Base
      ID_KEYWORD = 'id'
      SUPPORTED_FORMATS = Set[
        'date-time',
        'email',
        'hostname',
        'ipv4',
        'ipv6',
        'uri',
        'regex'
      ].freeze

    private

      def id_keyword
        ID_KEYWORD
      end

      def supported_format?(format)
        SUPPORTED_FORMATS.include?(format)
      end

      def validate_exclusive_maximum(data, schema, pointer, exclusive_maximum, maximum)
        yield error(data, schema, pointer, 'exclusiveMaximum') if exclusive_maximum && data >= maximum
      end

      def validate_exclusive_minimum(data, schema, pointer, exclusive_minimum, minimum)
        yield error(data, schema, pointer, 'exclusiveMinimum') if exclusive_minimum && data <= minimum
      end

      def validate_integer(data, schema, pointer)
        if !data.is_a?(Integer)
          yield error(data, schema, pointer, 'integer')
          return
        end

        validate_numeric(data, schema, pointer, &Proc.new)
      end
    end
  end
end
