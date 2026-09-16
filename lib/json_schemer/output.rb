# frozen_string_literal: true
module JSONSchemer
  module Output
    FRAGMENT_ENCODE_REGEX = /[^\w?\/:@\-.~!$&'()*+,;=]/

    attr_reader :keyword, :schema

    def x_error
      return @x_error if defined?(@x_error)
      @x_error = schema.parsed['x-error']&.message(error_key)
    end

  private

    def result(instance, instance_location, keyword_location, valid, nested = nil, type: nil, annotation: nil, details: nil, ignore_nested: false)
      Result.new(self, instance, instance_location, keyword_location, valid, nested, type, annotation, details, ignore_nested, valid ? 'annotations' : 'errors')
    end

    def escaped_keyword
      @escaped_keyword ||= Location.escape_json_pointer_token(keyword)
    end

    def join_location(location, keyword)
      Location.join(location, keyword)
    end

    def fragment_encode(location)
      Format.percent_encode(location, FRAGMENT_ENCODE_REGEX)
    end

    # :nocov:
    if Symbol.method_defined?(:name)
      def stringify(key)
        key.is_a?(Symbol) ? key.name : key.to_s
      end
    else
      def stringify(key)
        key.to_s
      end
    end
    # :nocov:

    def deep_stringify_keys(obj)
      case obj
      when Hash
        out = nil
        obj.each do |key, value|
          stringified_key = stringify(key)
          stringified_value = deep_stringify_keys(value)
          if out
            out[stringified_key] = stringified_value
          elsif !key.is_a?(String) || !stringified_value.equal?(value)
            out = {}
            obj.each do |previous_key, previous_value|
              break if previous_key.equal?(key)
              out[previous_key] = previous_value
            end
            out[stringified_key] = stringified_value
          end
        end
        out || obj
      when Array
        out = nil
        obj.each_with_index do |item, index|
          stringified_item = deep_stringify_keys(item)
          if out
            out << stringified_item
          elsif !stringified_item.equal?(item)
            out = obj.take(index)
            out << stringified_item
          end
        end
        out || obj
      else
        obj
      end
    end
  end
end
