# frozen_string_literal: true
module JSONSchemer
  class Keyword
    include Output

    attr_reader :value, :parent, :root, :parsed

    def initialize(value, parent, keyword)
      @value = value
      @parent = parent
      @root = parent.root
      @keyword = keyword
      @schema = parent
      @parsed = parse
    end

    def validate(_instance, _instance_location, _keyword_location, _dynamic_scope, _adjacent_results)
      nil
    end

    def absolute_keyword_location
      @absolute_keyword_location ||= "#{parent.absolute_keyword_location}/#{fragment_encode(escaped_keyword)}"
    end

    def schema_pointer
      @schema_pointer ||= "#{parent.schema_pointer}/#{escaped_keyword}"
    end

  private

    def parse
      value
    end

    def subschema(value, keyword = nil, **options)
      options[:base_uri] ||= parent.base_uri
      options[:meta_schema] ||= parent.meta_schema
      Schema.new(value, self, root, keyword, **options)
    end
  end
end
