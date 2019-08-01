# frozen_string_literal: true

module JSONSchemer
  module Schema
    class OpenApi3 < Draft7
      def validate_type(instance, type, &block)
        return if instance.schema['nullable'] && instance.data.nil?
        super
      end

      def discriminate(many_of, discriminator, data)
        return many_of unless many_of && discriminator

        property_value = data[discriminator['propertyName']]
        return [] if property_value.nil?

        schema_name = discriminator.dig('mapping', property_value) || property_value

        many_of.select do |item|
          File.basename(item['$ref']) == File.basename(schema_name)
        end
      end

      def many_of(instance, type, &block)
        schema = instance.schema
        discriminator = schema['discriminator']

        many_of = schema[type]
        many_of = discriminate(many_of, discriminator, instance.data) if many_of && discriminator

        if many_of&.empty? && discriminator
          yield error(instance, 'discriminator')
          return
        end

        many_of
      end
    end
  end
end
