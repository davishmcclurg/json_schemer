# frozen_string_literal: true
module JSONSchemer
  module Draft202012
    module Vocab
      module Validation
        class Type < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            case value
            when String
              result(instance, instance_location, keyword_location, valid_type(value, instance), :error => value)
            when Array
              result(instance, instance_location, keyword_location, value.any? { |type| valid_type(type, instance) })
            end
          end

        private

          def valid_type(type, instance)
            case type
            when 'null'
              instance.nil?
            when 'boolean'
              instance == true || instance == false
            when 'number'
              instance.is_a?(Numeric)
            when 'integer'
              instance.is_a?(Numeric) && (instance.is_a?(Integer) || instance.floor == instance)
            when 'string'
              instance.is_a?(String)
            when 'array'
              instance.is_a?(Array)
            when 'object'
              instance.is_a?(Hash)
            else
              true
            end
          end
        end

        class Enum < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !value || value.include?(instance))
          end
        end

        class Const < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, value == instance)
          end
        end

        class MultipleOf < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Numeric) || BigDecimal(instance.to_s).modulo(value).zero?)
          end
        end

        class Maximum < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Numeric) || instance <= value)
          end
        end

        class ExclusiveMaximum < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Numeric) || instance < value)
          end
        end

        class Minimum < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Numeric) || instance >= value)
          end
        end

        class ExclusiveMinimum < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Numeric) || instance > value)
          end
        end

        class MaxLength < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(String) || instance.size <= value)
          end
        end

        class MinLength < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(String) || instance.size >= value)
          end
        end

        class Pattern < Keyword
          def parse
            root.resolve_regexp(value)
          end

          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(String) || parsed.match?(instance))
          end
        end

        class MaxItems < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Array) || instance.size <= value)
          end
        end

        class MinItems < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Array) || instance.size >= value)
          end
        end

        class UniqueItems < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Array) || value == false || instance.size == instance.uniq.size)
          end
        end

        class MaxContains < Keyword
          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array) && context.adjacent_results.key?(Applicator::Contains)
            evaluated_items = context.adjacent_results.fetch(Applicator::Contains).annotation
            result(instance, instance_location, keyword_location, evaluated_items.size <= value)
          end
        end

        class MinContains < Keyword
          def validate(instance, instance_location, keyword_location, context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Array) && context.adjacent_results.key?(Applicator::Contains)
            evaluated_items = context.adjacent_results.fetch(Applicator::Contains).annotation
            result(instance, instance_location, keyword_location, evaluated_items.size >= value)
          end
        end

        class MaxProperties < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Hash) || instance.size <= value)
          end
        end

        class MinProperties < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            result(instance, instance_location, keyword_location, !instance.is_a?(Hash) || instance.size >= value)
          end
        end

        class Required < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)
            missing_keys = value - instance.keys
            result(instance, instance_location, keyword_location, missing_keys.none?, :details => { 'missing_keys' => missing_keys })
          end
        end

        class DependentRequired < Keyword
          def validate(instance, instance_location, keyword_location, _context)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(Hash)

            existing_keys = instance.keys

            nested = value.select do |key, _required_keys|
              instance.key?(key)
            end.map do |key, required_keys|
              result(instance, join_location(instance_location, key), join_location(keyword_location, key), (required_keys - existing_keys).none?)
            end

            result(instance, instance_location, keyword_location, nested.all?(&:valid), nested)
          end
        end
      end
    end
  end
end
