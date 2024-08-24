# frozen_string_literal: true

module JSONSchemer
  class Resources

    def initialize
      @resources ||= { :lexical => {}, :dynamic => {} }
    end

    def register(type, namespace_uri, schema)
      @resources[type][namespace_uri.to_s] = schema
    end

    def lexical!(namespace_uri)
      @resources[:lexical].fetch(namespace_uri.to_s)
    end

    def lexical(namespace_uri)
      @resources[:lexical][namespace_uri.to_s]
    end

    def dynamic!(namespace_uri)
      @resources[:dynamic].fetch(namespace_uri.to_s)
    end

    def dynamic?(namespace_uri)
      @resources[:dynamic].key?(namespace_uri.to_s)
    end
  end
end
