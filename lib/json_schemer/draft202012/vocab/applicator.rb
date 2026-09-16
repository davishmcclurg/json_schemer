# frozen_string_literal: true
module JSONSchemer
  module Draft202012
    module Vocab
      module Applicator
        class AllOf < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match all `allOf` schemas"
          end

          def parse
            value.map.with_index do |subschema, index|
              subschema(subschema, index.to_s)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            nested = parsed.map.with_index do |subschema, index|
              subschema.validate_instance(instance, instance_location, join_location(keyword_location, index.to_s), context)
            end
            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested)
          end

          def valid_instance?(instance, context)
            parsed.each do |subschema|
              valid = subschema.valid_instance?(instance, context)
              return nil if valid.nil?
              return false unless valid
            end
            true
          end
        end

        class AnyOf < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match any `anyOf` schemas"
          end

          def parse
            value.map.with_index do |subschema, index|
              subschema(subschema, index.to_s)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            nested = parsed.map.with_index do |subschema, index|
              subschema.validate_instance(instance, instance_location, join_location(keyword_location, index.to_s), context)
            end
            result(instance, instance_location, keyword_location, nested.any?(&:valid), nested)
          end

          def valid_instance?(instance, context)
            saw_supported = false
            parsed.each do |subschema|
              valid = subschema.valid_instance?(instance, context)
              return nil if valid.nil?
              saw_supported = true
              return true if valid
            end
            !saw_supported ? nil : false
          end
        end

        class OneOf < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match exactly one `oneOf` schema"
          end

          def parse
            value.map.with_index do |subschema, index|
              subschema(subschema, index.to_s)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            nested = parsed.map.with_index do |subschema, index|
              subschema.validate_instance(instance, instance_location, join_location(keyword_location, index.to_s), context)
            end
            valid_count = nested.count(&:valid)
            result(instance, instance_location, keyword_location, valid_count == 1, nested, :ignore_nested => valid_count > 1)
          end

          def valid_instance?(instance, context)
            valid_count = 0
            parsed.each do |subschema|
              valid = subschema.valid_instance?(instance, context)
              return nil if valid.nil?
              valid_count += 1 if valid
              return false if valid_count > 1
            end
            valid_count == 1
          end
        end

        class Not < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} matches `not` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            subschema_result = parsed.validate_instance(instance, instance_location, keyword_location, context)
            result(instance, instance_location, keyword_location, !subschema_result.valid, subschema_result.nested)
          end

          def valid_instance?(instance, context)
            valid = parsed.valid_instance?(instance, context)
            valid.nil? ? nil : !valid
          end
        end

        class If < Keyword
          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            subschema_result = parsed.validate_instance(instance, instance_location, keyword_location, context)
            result(instance, instance_location, keyword_location, true, subschema_result.nested, :annotation => subschema_result.valid)
          end

        end

        class Then < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match conditional `then` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return unless context.adjacent_results.key?(If) && context.adjacent_results.fetch(If).annotation
            subschema_result = parsed.validate_instance(instance, instance_location, keyword_location, context)
            result(instance, instance_location, keyword_location, subschema_result.valid, subschema_result.nested)
          end

        end

        class Else < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match conditional `else` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return unless context.adjacent_results.key?(If) && !context.adjacent_results.fetch(If).annotation
            subschema_result = parsed.validate_instance(instance, instance_location, keyword_location, context)
            result(instance, instance_location, keyword_location, subschema_result.valid, subschema_result.nested)
          end

        end

        class DependentSchemas < Keyword
          def error(formatted_instance_location:, **)
            "value at #{formatted_instance_location} does not match applicable `dependentSchemas` schemas"
          end

          def parse
            value.each_with_object({}) do |(key, subschema), out|
              out[key] = subschema(subschema, key)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            valid = true
            nested = []
            parsed.each do |key, subschema|
              next unless instance.key?(key)
              nested_result = subschema.validate_instance(instance, instance_location, join_location(keyword_location, key), context)
              valid &&= nested_result.valid
              nested << nested_result
            end

            result(instance, instance_location, keyword_location, valid, nested)
          end

        end

        class PrefixItems < Keyword
          def error(formatted_instance_location:, **)
            "array items at #{formatted_instance_location} do not match corresponding `prefixItems` schemas"
          end

          def parse
            value.map.with_index do |subschema, index|
              subschema(subschema, index.to_s)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            valid = true
            nested = []
            limit = instance.size < parsed.size ? instance.size : parsed.size
            limit.times do |index|
              index_name = index.to_s
              nested_result = parsed.fetch(index).validate_instance(instance.fetch(index), join_location(instance_location, index_name), join_location(keyword_location, index_name), context)
              valid &&= nested_result.valid
              nested << nested_result
            end

            result(instance, instance_location, keyword_location, valid, nested, :annotation => (nested.size - 1))
          end

          def valid_instance?(instance, context)
            return true unless instance.is_a?(Array)

            limit = instance.size < parsed.size ? instance.size : parsed.size
            limit.times do |index|
              valid = parsed.fetch(index).valid_instance?(instance.fetch(index), context)
              return nil if valid.nil?
              return false unless valid
            end

            true
          end
        end

        class Items < Keyword
          def error(formatted_instance_location:, **)
            "array items at #{formatted_instance_location} do not match `items` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            evaluated_index = context.adjacent_results[PrefixItems]&.annotation
            offset = evaluated_index ? (evaluated_index + 1) : 0

            valid = true
            nested = []
            index = offset
            while index < instance.size
              nested_result = parsed.validate_instance(instance.fetch(index), join_location(instance_location, index.to_s), keyword_location, context)
              valid &&= nested_result.valid
              nested << nested_result
              index += 1
            end

            result(instance, instance_location, keyword_location, valid, nested, :annotation => nested.any?)
          end

          def valid_instance?(instance, context)
            return true unless instance.is_a?(Array)
            return nil if schema.parsed.key?('prefixItems')

            instance.each do |item|
              valid = parsed.valid_instance?(item, context)
              return nil if valid.nil?
              return false unless valid
            end

            true
          end
        end

        class Contains < Keyword
          def error(formatted_instance_location:, **)
            "array at #{formatted_instance_location} does not contain enough items that match `contains` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            nested = []
            annotation = []
            instance.each_with_index do |item, index|
              nested_result = parsed.validate_instance(item, join_location(instance_location, index.to_s), keyword_location, context)
              nested << nested_result
              annotation << index if nested_result.valid
            end

            min_contains = schema.parsed['minContains']&.parsed || 1

            result(instance, instance_location, keyword_location, annotation.size >= min_contains, nested, :annotation => annotation, :ignore_nested => true)
          end

        end

        class Properties < Keyword
          def error(formatted_instance_location:, **)
            "object properties at #{formatted_instance_location} do not match corresponding `properties` schemas"
          end

          def parse
            value.each_with_object({}) do |(property, subschema), out|
              out[property] = subschema(subschema, property)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            if root.before_property_validation.any?
              original_instance = context.original_instance(instance_location)
              root.before_property_validation.each do |hook|
                parsed.each do |property, subschema|
                  hook.call(original_instance, property, subschema.value, schema.value)
                end
              end
              instance.replace(deep_stringify_keys(original_instance))
            end

            evaluated_keys = []
            nested = []

            parsed.each do |property, subschema|
              if instance.key?(property)
                evaluated_keys << property
                nested << subschema.validate_instance(instance.fetch(property), join_location(instance_location, property), join_location(keyword_location, property), context)
              end
            end

            if root.after_property_validation.any?
              original_instance = context.original_instance(instance_location)
              root.after_property_validation.each do |hook|
                parsed.each do |property, subschema|
                  hook.call(original_instance, property, subschema.value, schema.value)
                end
              end
              instance.replace(deep_stringify_keys(original_instance))
            end

            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested, :annotation => evaluated_keys)
          end

          def valid_instance?(instance, context)
            return true unless instance.is_a?(Hash)
            return nil if root.before_property_validation.any? || root.after_property_validation.any?

            parsed.each do |property, subschema|
              next unless instance.key?(property)
              valid = subschema.valid_instance?(instance.fetch(property), context)
              return nil if valid.nil?
              return false unless valid
            end

            true
          end
        end

        class PatternProperties < Keyword
          def error(formatted_instance_location:, **)
            "object properties at #{formatted_instance_location} do not match corresponding `patternProperties` schemas"
          end

          def parse
            value.each_with_object({}) do |(pattern, subschema), out|
              out[pattern] = subschema(subschema, pattern)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            evaluated = Set[]
            nested = []

            parsed.each do |pattern, subschema|
              regexp = root.resolve_regexp(pattern)
              instance.each do |key, value|
                if regexp.match?(key)
                  evaluated << key
                  nested << subschema.validate_instance(value, join_location(instance_location, key), join_location(keyword_location, pattern), context)
                end
              end
            end

            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested, :annotation => evaluated.to_a)
          end
        end

        class AdditionalProperties < Keyword
          def error(formatted_instance_location:, **)
            "object properties at #{formatted_instance_location} do not match `additionalProperties` schema"
          end

          def false_schema_error(formatted_instance_location:, **)
            "object property at #{formatted_instance_location} is a disallowed additional property"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            property_keys = context.adjacent_results[Properties]&.annotation || []
            pattern_property_keys = context.adjacent_results[PatternProperties]&.annotation || []

            valid = true
            nested = []
            evaluated = []
            instance.each do |key, value|
              next if property_keys.include?(key) || pattern_property_keys.include?(key)
              nested_result = parsed.validate_instance(value, join_location(instance_location, key), keyword_location, context)
              valid &&= nested_result.valid
              nested << nested_result
              evaluated << key
            end

            result(instance, instance_location, keyword_location, valid, nested, :annotation => evaluated)
          end

          def valid_instance?(instance, context)
            return true unless instance.is_a?(Hash)

            property_keys = schema.parsed['properties']&.parsed&.keys || []
            return nil if schema.parsed.key?('patternProperties')

            instance.each do |key, value|
              next if property_keys.include?(key)
              valid = parsed.valid_instance?(value, context)
              return nil if valid.nil?
              return false unless valid
            end

            true
          end
        end

        class PropertyNames < Keyword
          def error(formatted_instance_location:, **)
            "object property names at #{formatted_instance_location} do not match `propertyNames` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            valid = true
            nested = []
            instance.each_key do |key|
              nested_result = parsed.validate_instance(key, instance_location, keyword_location, context)
              valid &&= nested_result.valid
              nested << nested_result
            end

            result(instance, instance_location, keyword_location, valid, nested)
          end

        end

        class Dependencies < Keyword
          def error(formatted_instance_location:, **)
            "object at #{formatted_instance_location} either does not match applicable `dependencies` schemas or is missing required `dependencies` properties"
          end

          def parse
            value.each_with_object({}) do |(key, value), out|
              out[key] = value.is_a?(Array) ? value : subschema(value, key)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            valid = true
            nested = []
            parsed.each do |key, value|
              next unless instance.key?(key)
              nested_result = if value.is_a?(Array)
                missing_keys = value.reject { |required_key| instance.key?(required_key) }
                result(instance, instance_location, join_location(keyword_location, key), missing_keys.none?, :details => { 'missing_keys' => missing_keys })
              else
                value.validate_instance(instance, instance_location, join_location(keyword_location, key), context)
              end
              valid &&= nested_result.valid
              nested << nested_result
            end

            result(instance, instance_location, keyword_location, valid, nested)
          end

        end
      end
    end
  end
end
