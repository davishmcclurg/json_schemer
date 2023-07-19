# frozen_string_literal: true
module JSONSchemer
  module Draft202012
    module Vocab
      module FormatAssertion
        class Format < Keyword
          extend JSONSchemer::Format

          DEFAULT_FORMAT = proc do |instance, value|
            !instance.is_a?(String) || valid_spec_format?(instance, value)
          end

          def parse
            root.format && root.formats.fetch(value, DEFAULT_FORMAT)
          end

          def validate(instance, instance_location, keyword_location, _context)
            valid = parsed == false || parsed.call(instance, value)
            result(instance, instance_location, keyword_location, valid, :annotation => value)
          end
        end
      end
    end
  end
end
