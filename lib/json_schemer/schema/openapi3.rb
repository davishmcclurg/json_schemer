# frozen_string_literal: true

module JSONSchemer
  module Schema
    class OpenApi3 < Draft4
      def validate_type(instance, type, &block)
        return if instance.schema['nullable'] && instance.data.nil?
        super
      end

      def discriminate(many_of, discriminator, data)
        return many_of unless many_of && discriminator

        property_name = discriminator['propertyName']
        schema_name = data[property_name]
        filtered = many_of.filter do |item|
          resolve_schema_name(item) == schema_name
        end
        filtered
      end

      def resolve_schema_name(item)
        File.basename(item['$ref'])
      end
    end
  end
end
