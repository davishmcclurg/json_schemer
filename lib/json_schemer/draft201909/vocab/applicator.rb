# frozen_string_literal: true
module JSONSchemer
  module Draft201909
    module Vocab
      module Applicator
        class Items < Keyword
          def error(formatted_instance_location:, **)
            "array items at #{formatted_instance_location} do not match `items` schema(s)"
          end

          def parse
            if value.is_a?(Array)
              value.map.with_index do |subschema, index|
                subschema(subschema, index.to_s)
              end
            else
              subschema(value)
            end
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            nested = if parsed.is_a?(Array)
              valid = true
              nested_results = []
              limit = instance.size < parsed.size ? instance.size : parsed.size
              limit.times do |index|
                nested_result = parsed.fetch(index).validate_instance(instance.fetch(index), join_location(instance_location, index.to_s), join_location(keyword_location, index.to_s), context)
                valid &&= nested_result.valid
                nested_results << nested_result
              end
              nested_results
            else
              valid = true
              nested_results = []
              instance.each_with_index do |item, index|
                nested_result = parsed.validate_instance(item, join_location(instance_location, index.to_s), keyword_location, context)
                valid &&= nested_result.valid
                nested_results << nested_result
              end
              nested_results
            end

            result(instance, instance_location, keyword_location, valid, nested, :annotation => (nested.size - 1))
          end

        end

        class AdditionalItems < Keyword
          def error(formatted_instance_location:, **)
            "array items at #{formatted_instance_location} do not match `additionalItems` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            evaluated_index = context.adjacent_results[Items]&.annotation
            offset = evaluated_index ? (evaluated_index + 1) : instance.size

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

        end

        class UnevaluatedItems < Keyword
          def error(formatted_instance_location:, **)
            "array items at #{formatted_instance_location} do not match `unevaluatedItems` schema"
          end

          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array)

            unevaluated_items = instance.size.times.to_set

            context.adjacent_results.each_value do |adjacent_result|
              collect_unevaluated_items(adjacent_result, instance_location, unevaluated_items)
            end

            valid = true
            nested = []
            unevaluated_items.each do |index|
              nested_result = parsed.validate_instance(instance.fetch(index), join_location(instance_location, index.to_s), keyword_location, context)
              valid &&= nested_result.valid
              nested << nested_result
            end

            result(instance, instance_location, keyword_location, valid, nested, :annotation => nested.any?)
          end

        private

          def collect_unevaluated_items(result, instance_location, unevaluated_items)
            return unless result.valid && result.instance_location == instance_location
            case result.source
            when Items
              unevaluated_items.subtract(0..result.annotation)
            when AdditionalItems, UnevaluatedItems
              unevaluated_items.clear if result.annotation
            end
            result.nested&.each do |nested_result|
              collect_unevaluated_items(nested_result, instance_location, unevaluated_items)
            end
          end
        end
      end
    end
  end
end
