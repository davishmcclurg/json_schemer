# frozen_string_literal: true
module JSONSchemer
  module Draft4
    module Vocab
      module Validation
        class Type < Draft202012::Vocab::Validation::Type
        private
          def valid_type(type, instance)
            type == 'integer' ? instance.is_a?(Integer) : super
          end
        end

        class ExclusiveMaximum < Keyword
          def validate(instance, instance_location, keyword_location, _dynamic_scope, _adjacent_results)
            maximum = schema.parsed.fetch('maximum').parsed
            valid = !instance.is_a?(Numeric) || !value || !maximum || instance < maximum
            result(instance, instance_location, keyword_location, valid)
          end
        end

        class ExclusiveMinimum < Keyword
          def validate(instance, instance_location, keyword_location, _dynamic_scope, _adjacent_results)
            minimum = schema.parsed.fetch('minimum').parsed
            valid = !instance.is_a?(Numeric) || !value || !minimum || instance > minimum
            result(instance, instance_location, keyword_location, valid)
          end
        end
      end
    end
  end
end