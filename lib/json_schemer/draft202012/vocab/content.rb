# frozen_string_literal: true
module JSONSchemer
  module Draft202012
    module Vocab
      module Content
        class ContentEncoding < Keyword
          def validate(instance, instance_location, keyword_location, _dynamic_scope, _adjacent_results)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(String)

            _valid, annotation = Format.decode_content_encoding(instance, value)

            result(instance, instance_location, keyword_location, true, :annotation => annotation)
          end
        end

        class ContentMediaType < Keyword
          def validate(instance, instance_location, keyword_location, _dynamic_scope, adjacent_results)
            return result(instance, instance_location, keyword_location, true) unless instance.is_a?(String)

            decoded_instance = adjacent_results[ContentEncoding]&.annotation || instance
            _valid, annotation = Format.parse_content_media_type(decoded_instance, value)

            result(instance, instance_location, keyword_location, true, :annotation => annotation)
          end
        end

        class ContentSchema < Keyword
          def parse
            subschema(value)
          end

          def validate(instance, instance_location, keyword_location, dynamic_scope, adjacent_results)
            return result(instance, instance_location, keyword_location, true) unless adjacent_results.key?(ContentMediaType)

            parsed_instance = adjacent_results.fetch(ContentMediaType).annotation
            annotation = parsed.validate_instance(parsed_instance, instance_location, keyword_location, dynamic_scope)

            result(instance, instance_location, keyword_location, true, :annotation => annotation.to_output_unit)
          end
        end
      end
    end
  end
end
