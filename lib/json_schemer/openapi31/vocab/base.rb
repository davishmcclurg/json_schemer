# frozen_string_literal: true
module JSONSchemer
  module OpenAPI31
    module Vocab
      module Base
        class AllOf < Draft202012::Vocab::Applicator::AllOf
          attr_accessor :skip_ref_once

          def validate(instance, instance_location, keyword_location, context)
            nested = []
            parsed.each_with_index do |subschema, index|
              if ref_schema = subschema.parsed['$ref']&.ref_schema
                next if skip_ref_once == ref_schema.absolute_keyword_location
                ref_schema.parsed['discriminator']&.skip_ref_once = schema.absolute_keyword_location
              end
              nested << subschema.validate_instance(instance, instance_location, join_location(keyword_location, index.to_s), context)
            end
            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested)
          ensure
            self.skip_ref_once = nil
          end
        end

        class AnyOf < Draft202012::Vocab::Applicator::AnyOf
          def validate(*)
            schema.parsed.key?('discriminator') ? nil : super
          end
        end

        class OneOf < Draft202012::Vocab::Applicator::OneOf
          def validate(*)
            schema.parsed.key?('discriminator') ? nil : super
          end
        end

        class Discriminator < Keyword
          include Format::JSONPointer

          attr_accessor :skip_ref_once

          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match `discriminator` schema"
          end

          def validate(instance, instance_location, keyword_location, context)
            property_name = value.fetch('propertyName')
            mapping = value['mapping'] || {}

            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)
            return result(instance, instance_location, keyword_location, false) unless instance.key?(property_name)

            property = instance.fetch(property_name)
            ref = mapping.fetch(property, property)

            ref_schema = nil
            unless ref.start_with?('#') && valid_json_pointer?(ref.delete_prefix('#'))
              ref_schema = begin
                root.resolve_ref(URI.join(schema.base_uri, "#/components/schemas/#{ref}"))
              rescue InvalidRefPointer
                nil
              end
            end
            ref_schema ||= root.resolve_ref(URI.join(schema.base_uri, ref))

            return if skip_ref_once == ref_schema.absolute_keyword_location

            nested = []

            if schema.parsed.key?('anyOf') || schema.parsed.key?('oneOf')
              subschemas = schema.parsed['anyOf']&.parsed || []
              subschemas += schema.parsed['oneOf']&.parsed || []
              subschemas.each do |subschema|
                if subschema.parsed.fetch('$ref').ref_schema.absolute_keyword_location == ref_schema.absolute_keyword_location
                  nested << subschema.validate_instance(instance, instance_location, keyword_location, context)
                end
              end
            else
              ref_schema.parsed['allOf']&.skip_ref_once = schema.absolute_keyword_location
              nested << ref_schema.validate_instance(instance, instance_location, keyword_location, context)
            end

            result(instance, instance_location, keyword_location, (nested.any? && nested.all?(&:valid)), nested)
          ensure
            self.skip_ref_once = nil
          end
        end
      end
    end
  end
end
