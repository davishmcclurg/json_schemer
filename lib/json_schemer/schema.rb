# frozen_string_literal: true
module JSONSchemer
  class Schema
    include Output
    include Format::JSONPointer

    DEFAULT_SCHEMA = Draft202012::BASE_URI.to_s.freeze
    UNKNOWN_KEYWORD_CLASS = Draft202012::Vocab::Core::UnknownKeyword
    DEFAULT_BASE_URI = URI('json-schemer://schema').freeze
    DEFAULT_FORMATS = {}.freeze
    DEFAULT_KEYWORDS = {}.freeze
    DEFAULT_BEFORE_PROPERTY_VALIDATION = [].freeze
    DEFAULT_AFTER_PROPERTY_VALIDATION = [].freeze
    DEFAULT_REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
    NET_HTTP_REF_RESOLVER = proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
    RUBY_REGEXP_RESOLVER = proc { |pattern| Regexp.new(pattern) }
    ECMA_REGEXP_RESOLVER = proc { |pattern| Regexp.new(EcmaRegexp.ruby_equivalent(pattern)) }

    INSERT_PROPERTY_DEFAULTS = proc do |instance, property, property_schema, _parent_schema|
      if !instance.key?(property) && property_schema.is_a?(Hash) && property_schema.key?('default')
        instance[property] = property_schema.fetch('default').clone
      end
    end

    attr_accessor :base_uri, :meta_schema, :keywords, :keyword_order
    attr_reader :value, :parent, :root, :parsed
    attr_reader :vocabulary, :format, :formats, :custom_keywords, :before_property_validation, :after_property_validation

    def initialize(
      value,
      parent = nil,
      root = self,
      keyword = nil,
      # fixme: allow relative?
      base_uri: DEFAULT_BASE_URI,
      meta_schema: nil,
      vocabulary: nil,
      format: true,
      formats: DEFAULT_FORMATS,
      keywords: DEFAULT_KEYWORDS,
      before_property_validation: DEFAULT_BEFORE_PROPERTY_VALIDATION,
      after_property_validation: DEFAULT_AFTER_PROPERTY_VALIDATION,
      insert_property_defaults: false,
      ref_resolver: DEFAULT_REF_RESOLVER,
      regexp_resolver: 'ruby',
      output_format: 'classic'
    )
      @value = value
      @parent = parent
      @root = root
      @keyword = keyword
      @schema = self
      @base_uri = base_uri
      @meta_schema = meta_schema
      @vocabulary = vocabulary
      @format = format
      @formats = formats
      @custom_keywords = keywords
      @before_property_validation = Array(before_property_validation)
      @before_property_validation = [INSERT_PROPERTY_DEFAULTS, *before_property_validation] if insert_property_defaults
      @after_property_validation = Array(after_property_validation)
      @original_ref_resolver = ref_resolver
      @original_regexp_resolver = regexp_resolver
      @output_format = output_format
      @parsed = parse
    end

    def valid?(instance)
      validate(instance, :output_format => 'flag').fetch('valid')
    end

    def validate(instance, output_format: @output_format)
      result = validate_instance(instance, Location.root, root_keyword_location, [])
      case output_format
      when 'classic'
        result.classic
      when 'flag'
        result.flag
      when 'basic'
        result.basic
      when 'detailed'
        result.detailed
      when 'verbose'
        result.verbose
      else
        raise UnknownOutputFormat, output_format
      end
    end

    def valid_schema?
      meta_schema.valid?(value)
    end

    def validate_schema
      meta_schema.validate(value)
    end

    def validate_instance(instance, instance_location, keyword_location, dynamic_scope)
      dynamic_scope.push(self)

      begin
        return result(instance, instance_location, keyword_location, false) if value == false
        return result(instance, instance_location, keyword_location, true) if value == true || value.empty?

        valid = true
        nested = []
        adjacent_results = {}

        parsed.each do |keyword, keyword_instance|
          next unless keyword_result = keyword_instance.validate(instance, instance_location, join_location(keyword_location, keyword), dynamic_scope, adjacent_results)
          valid &&= keyword_result.valid
          nested << keyword_result
          adjacent_results[keyword_instance.class] = keyword_result
        end

        if custom_keywords.any?
          custom_keywords.each do |custom_keyword, callable|
            if value.key?(custom_keyword)
              [*callable.call(instance, value, instance_location)].each do |custom_keyword_result|
                valid &&= (custom_keyword_result == true)
                error = custom_keyword_result.is_a?(String) ? custom_keyword_result : custom_keyword
                nested << result(instance, instance_location, keyword_location, custom_keyword_result == true, :error => error)
              end
            end
          end
        end

        result(instance, instance_location, keyword_location, valid, nested)
      ensure
        dynamic_scope.pop
      end
    end

    def resolve_ref(uri)
      pointer = ''
      if valid_json_pointer?(uri.fragment)
        pointer = URI.decode_www_form_component(uri.fragment)
        uri.fragment = nil
      end

      lexical_resources = resources.fetch(:lexical)
      schema = lexical_resources[uri]

      if !schema && uri.fragment.nil?
        empty_fragment_uri = uri.dup
        empty_fragment_uri.fragment = ''
        schema = lexical_resources[empty_fragment_uri]
      end

      unless schema
        location_independent_identifier = uri.fragment
        uri.fragment = nil
        remote_schema = JSONSchemer.schema(
          ref_resolver.call(uri) || raise(InvalidRefResolution, uri.to_s),
          :base_uri => uri,
          :meta_schema => meta_schema,
          :format => format,
          :formats => formats,
          :keywords => custom_keywords,
          :before_property_validation => before_property_validation,
          :after_property_validation => after_property_validation,
          :ref_resolver => ref_resolver,
          :regexp_resolver => regexp_resolver
        )
        remote_uri = remote_schema.base_uri.dup
        remote_uri.fragment = location_independent_identifier if location_independent_identifier
        schema = remote_schema.resources.fetch(:lexical).fetch(remote_uri)
      end

      schema = Hana::Pointer.parse(pointer).reduce(schema) do |obj, token|
        obj.parsed.is_a?(Array) ? obj.parsed.fetch(token.to_i) : obj.parsed.fetch(token)
      end

      schema = schema.schema! unless schema.is_a?(Schema)

      schema
    end

    def resolve_regexp(pattern)
      regexp_resolver.call(pattern) || raise(InvalidRegexpResolution, pattern)
    end

    def absolute_keyword_location
      # using `equal?` because `URI::Generic#==` is slow
      @absolute_keyword_location ||= if !parent || (!parent.schema.base_uri.equal?(base_uri) && (base_uri.fragment.nil? || base_uri.fragment.empty?))
        absolute_keyword_location_uri = base_uri.dup
        absolute_keyword_location_uri.fragment = ''
        absolute_keyword_location_uri.to_s
      elsif keyword
        "#{parent.absolute_keyword_location}/#{fragment_encode(escaped_keyword)}"
      else
        parent.absolute_keyword_location
      end
    end

    def schema_pointer
      @schema_pointer ||= if !parent
        ''
      elsif keyword
        "#{parent.schema_pointer}/#{escaped_keyword}"
      else
        parent.schema_pointer
      end
    end

    def id_keyword
      @id_keyword ||= (parsed['$schema']&.parsed == Draft4::BASE_URI.to_s ? 'id' : '$id')
    end

    def resources
      @resources ||= { :lexical => {}, :dynamic => {} }
    end

  private

    def parse
      @parsed = {}

      if value.is_a?(Hash) && value.key?('$schema')
        @parsed['$schema'] = Draft202012::Vocab::Core::Schema.new(value.fetch('$schema'), self, '$schema')
      elsif root == self && !meta_schema
        Draft202012::Vocab::Core::Schema.new(DEFAULT_SCHEMA, self, '$schema')
      end

      if value.is_a?(Hash) && value.key?('$vocabulary')
        @parsed['$vocabulary'] = Draft202012::Vocab::Core::Vocabulary.new(value.fetch('$vocabulary'), self, '$vocabulary')
      elsif vocabulary
        Draft202012::Vocab::Core::Vocabulary.new(vocabulary, self, '$vocabulary')
      end

      if root == self && (!value.is_a?(Hash) || !value.key?(meta_schema.id_keyword))
        Draft202012::Vocab::Core::Id.new(base_uri, self, meta_schema.id_keyword)
      end

      if value.is_a?(Hash)
        keywords = meta_schema.keywords

        if value.key?('$ref') && keywords.fetch('$ref').exclusive?
          @parsed['$ref'] = keywords.fetch('$ref').new(value.fetch('$ref'), self, '$ref')
        else
          keyword_order = meta_schema.keyword_order
          last = keywords.size

          value.sort do |(keyword_a, _value_a), (keyword_b, _value_b)|
            keyword_order.fetch(keyword_a, last) <=> keyword_order.fetch(keyword_b, last)
          end.each do |keyword, value|
            raise InvalidSymbolKey, 'schemas must use string keys' unless keyword.is_a?(String)
            @parsed[keyword] ||= keywords.fetch(keyword, UNKNOWN_KEYWORD_CLASS).new(value, self, keyword)
          end
        end
      end

      @parsed
    end

    def root_keyword_location
      @root_keyword_location ||= Location.root
    end

    def ref_resolver
      @ref_resolver ||= @original_ref_resolver == 'net/http' ? CachedResolver.new(&NET_HTTP_REF_RESOLVER) : @original_ref_resolver
    end

    def regexp_resolver
      @regexp_resolver ||= case @original_regexp_resolver
      when 'ecma'
        CachedResolver.new(&ECMA_REGEXP_RESOLVER)
      when 'ruby'
        CachedResolver.new(&RUBY_REGEXP_RESOLVER)
      else
        @original_regexp_resolver
      end
    end
  end
end
