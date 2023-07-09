# frozen_string_literal: true
module JSONSchemer
  module Output
    FRAGMENT_ENCODE_REGEX = /[^\w?\/:@\-.~!$&'()*+,;=]/

    module ClassMethods
      def error
        @error ||= name.rpartition('::').last.sub(/\A[[:alpha:]]/, &:downcase)
      end
    end

    def self.included(klass)
      klass.extend(ClassMethods)
    end

    attr_reader :keyword, :schema

  private

    def result(instance, instance_location, keyword_location, valid, nested = nil, error: nil, annotation: nil, details: nil, ignore_nested: false)
      if valid
        Result.new(self, instance, instance_location, keyword_location, valid, nested, error, annotation, details, ignore_nested, 'annotations')
      else
        error ||= self.class.error
        Result.new(self, instance, instance_location, keyword_location, valid, nested, error, annotation, details, ignore_nested, 'errors')
      end
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
  end
end
