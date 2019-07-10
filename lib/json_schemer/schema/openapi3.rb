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

        property_name = discriminator['propertyName']
        property_value = data[property_name]
        schema_name = discriminator['mapping'][property_value] || property_value

        many_of.select do |item|
          resolve_schema_name(item) == File.basename(schema_name)
        end
      end

      def resolve_schema_name(item)
        File.basename(item['$ref'])
      end
    end
  end
end
