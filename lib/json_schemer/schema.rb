# frozen_string_literal: true
module JSONSchemer
  class Schema
    Context = Struct.new(:instance, :dynamic_scope, :adjacent_results, :short_circuit, :access_mode) do
      def original_instance(instance_location)
        Hana::Pointer.parse(Location.resolve(instance_location)).reduce(instance) do |obj, token|
          obj.fetch(obj.is_a?(Array) ? token.to_i : token)
        end
      end
    end

    include Output

    DEFAULT_SCHEMA = Draft202012::BASE_URI.to_s.freeze
    SCHEMA_KEYWORD_CLASS = Draft202012::Vocab::Core::Schema
    VOCABULARY_KEYWORD_CLASS = Draft202012::Vocab::Core::Vocabulary
    ID_KEYWORD_CLASS = Draft202012::Vocab::Core::Id
    UNKNOWN_KEYWORD_CLASS = Draft202012::Vocab::Core::UnknownKeyword
    NOT_KEYWORD_CLASS = Draft202012::Vocab::Applicator::Not
    PROPERTIES_KEYWORD_CLASS = Draft202012::Vocab::Applicator::Properties
    DEFAULT_BASE_URI = URI('json-schemer://schema').freeze
    DEFAULT_FORMATS = {}.freeze
    DEFAULT_CONTENT_ENCODINGS = {}.freeze
    DEFAULT_CONTENT_MEDIA_TYPES = {}.freeze
    DEFAULT_KEYWORDS = {}.freeze
    DEFAULT_BEFORE_PROPERTY_VALIDATION = [].freeze
    DEFAULT_AFTER_PROPERTY_VALIDATION = [].freeze
    DEFAULT_REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
    NET_HTTP_REF_RESOLVER = proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
    RUBY_REGEXP_RESOLVER = proc { |pattern| Regexp.new(pattern) }
    ECMA_REGEXP_RESOLVER = proc { |pattern| Regexp.new(EcmaRegexp.ruby_equivalent(pattern)) }

    DEFAULT_PROPERTY_DEFAULT_RESOLVER = proc do |instance, property, results_with_tree_validity|
      results_with_tree_validity = results_with_tree_validity.select(&:last) unless results_with_tree_validity.size == 1
      annotations = results_with_tree_validity.to_set { |result, _tree_valid| result.annotation }
      if annotations.size == 1
        instance[property] = annotations.first.clone
        true
      else
        false
      end
    end

    attr_accessor :base_uri, :meta_schema, :keywords, :keyword_order
    attr_reader :value, :parent, :root, :parsed
    attr_reader :vocabulary, :format, :formats, :content_encodings, :content_media_types, :custom_keywords, :before_property_validation, :after_property_validation, :insert_property_defaults, :property_default_resolver

    def initialize(
      value,
      parent = nil,
      root = self,
      keyword = nil,
      base_uri: DEFAULT_BASE_URI,
      meta_schema: nil,
      vocabulary: nil,
      format: true,
      formats: DEFAULT_FORMATS,
      content_encodings: DEFAULT_CONTENT_ENCODINGS,
      content_media_types: DEFAULT_CONTENT_MEDIA_TYPES,
      keywords: DEFAULT_KEYWORDS,
      before_property_validation: DEFAULT_BEFORE_PROPERTY_VALIDATION,
      after_property_validation: DEFAULT_AFTER_PROPERTY_VALIDATION,
      insert_property_defaults: false,
      property_default_resolver: DEFAULT_PROPERTY_DEFAULT_RESOLVER,
      ref_resolver: DEFAULT_REF_RESOLVER,
      regexp_resolver: 'ruby',
      output_format: 'classic',
      resolve_enumerators: false,
      access_mode: nil
    )
      @value = deep_stringify_keys(value)
      @parent = parent
      @root = root
      @keyword = keyword
      @schema = self
      @base_uri = base_uri
      @meta_schema = meta_schema
      @vocabulary = vocabulary
      @format = format
      @formats = formats
      @content_encodings = content_encodings
      @content_media_types = content_media_types
      @custom_keywords = keywords
      @before_property_validation = Array(before_property_validation)
      @after_property_validation = Array(after_property_validation)
      @insert_property_defaults = insert_property_defaults
      @property_default_resolver = property_default_resolver
      @original_ref_resolver = ref_resolver
      @original_regexp_resolver = regexp_resolver
      @output_format = output_format
      @resolve_enumerators = resolve_enumerators
      @access_mode = access_mode
      @parsed = parse
    end

    def valid?(instance, **options)
      validate(instance, :output_format => 'flag', **options).fetch('valid')
    end

    def validate(instance, output_format: @output_format, resolve_enumerators: @resolve_enumerators, access_mode: @access_mode)
      instance_location = Location.root
      context = Context.new(instance, [], nil, (!insert_property_defaults && output_format == 'flag'), access_mode)
      result = validate_instance(deep_stringify_keys(instance), instance_location, root_keyword_location, context)
      if insert_property_defaults && result.insert_property_defaults(context, &property_default_resolver)
        result = validate_instance(deep_stringify_keys(instance), instance_location, root_keyword_location, context)
      end
      output = result.output(output_format)
      resolve_enumerators!(output) if resolve_enumerators
      output
    end

    def valid_schema?
      meta_schema.valid?(value)
    end

    def validate_schema
      meta_schema.validate(value)
    end

    def ref(value)
      root.resolve_ref(URI.join(base_uri, value))
    end

    def validate_instance(instance, instance_location, keyword_location, context)
      context.dynamic_scope.push(self)
      original_adjacent_results = context.adjacent_results
      adjacent_results = context.adjacent_results = {}
      short_circuit = context.short_circuit

      begin
        return result(instance, instance_location, keyword_location, false) if value == false
        return result(instance, instance_location, keyword_location, true) if value == true || value.empty?

        valid = true
        nested = []

        parsed.each do |keyword, keyword_instance|
          next unless keyword_result = keyword_instance.validate(instance, instance_location, join_location(keyword_location, keyword), context)
          valid &&= keyword_result.valid
          return result(instance, instance_location, keyword_location, false) if short_circuit && !valid
          nested << keyword_result
          adjacent_results[keyword_instance.class] = keyword_result
        end

        if custom_keywords.any?
          custom_keywords.each do |custom_keyword, callable|
            if value.key?(custom_keyword)
              [*callable.call(instance, value, instance_location)].each do |custom_keyword_result|
                custom_keyword_valid = custom_keyword_result == true
                valid &&= custom_keyword_valid
                type = custom_keyword_result.is_a?(String) ? custom_keyword_result : custom_keyword
                details = { 'keyword' => custom_keyword, 'result' => custom_keyword_result }
                nested << result(instance, instance_location, keyword_location, custom_keyword_valid, :type => type, :details => details)
              end
            end
          end
        end

        result(instance, instance_location, keyword_location, valid, nested)
      ensure
        context.dynamic_scope.pop
        context.adjacent_results = original_adjacent_results
      end
    end

    def resolve_ref(uri)
      pointer = ''
      if Format.valid_json_pointer?(uri.fragment)
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
          :content_encodings => content_encodings,
          :content_media_types => content_media_types,
          :keywords => custom_keywords,
          :before_property_validation => before_property_validation,
          :after_property_validation => after_property_validation,
          :property_default_resolver => property_default_resolver,
          :ref_resolver => ref_resolver,
          :regexp_resolver => regexp_resolver
        )
        remote_uri = remote_schema.base_uri.dup
        remote_uri.fragment = location_independent_identifier if location_independent_identifier
        schema = remote_schema.resources.fetch(:lexical).fetch(remote_uri)
      end

      schema = Hana::Pointer.parse(pointer).reduce(schema) do |obj, token|
        obj.fetch(token)
      rescue IndexError
        raise InvalidRefPointer, pointer
      end

      schema = schema.parsed_schema if schema.is_a?(Keyword)
      raise InvalidRefPointer, pointer unless schema.is_a?(Schema)

      schema
    end

    def resolve_regexp(pattern)
      regexp_resolver.call(pattern) || raise(InvalidRegexpResolution, pattern)
    end

    def bundle
      return value unless value.is_a?(Hash)

      id_keyword = meta_schema.id_keyword
      defs_keyword = meta_schema.defs_keyword

      compound_document = value.dup
      compound_document[id_keyword] = base_uri.to_s
      compound_document['$schema'] = meta_schema.base_uri.to_s
      embedded_resources = compound_document[defs_keyword] = (compound_document[defs_keyword]&.dup || {})

      if compound_document.key?('$ref') && meta_schema.keywords.fetch('$ref').exclusive?
        compound_document['allOf'] = (compound_document['allOf']&.dup || [])
        compound_document['allOf'] << { '$ref' => compound_document.delete('$ref') }
      end

      values = [self]
      while value = values.shift
        case value
        when Schema
          values << value.parsed
        when Keyword
          if value.respond_to?(:ref_uri) && value.respond_to?(:ref_schema)
            ref_uri = value.ref_uri.dup
            ref_uri.fragment = nil
            ref_id = ref_uri.to_s
            ref_schema = value.ref_schema.root

            next if ref_schema == root || embedded_resources.key?(ref_id)

            embedded_resource = ref_schema.value.dup
            embedded_resource[id_keyword] = ref_id
            embedded_resource['$schema'] = ref_schema.meta_schema.base_uri.to_s
            embedded_resources[ref_id] = embedded_resource

            values << ref_schema
          else
            values << value.parsed
          end
        when Hash
          values.concat(value.values)
        when Array
          values.concat(value)
        end
      end

      compound_document
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

    def error_key
      '^'
    end

    def fetch(key)
      parsed.fetch(key)
    end

    def fetch_format(format, *args, &block)
      if meta_schema == self
        formats.fetch(format, *args, &block)
      else
        formats.fetch(format) { meta_schema.fetch_format(format, *args, &block) }
      end
    end

    def fetch_content_encoding(content_encoding, *args, &block)
      if meta_schema == self
        content_encodings.fetch(content_encoding, *args, &block)
      else
        content_encodings.fetch(content_encoding) { meta_schema.fetch_content_encoding(content_encoding, *args, &block) }
      end
    end

    def fetch_content_media_type(content_media_type, *args, &block)
      if meta_schema == self
        content_media_types.fetch(content_media_type, *args, &block)
      else
        content_media_types.fetch(content_media_type) { meta_schema.fetch_content_media_type(content_media_type, *args, &block) }
      end
    end

    def id_keyword
      @id_keyword ||= (keywords.key?('$id') ? '$id' : 'id')
    end

    def defs_keyword
      @defs_keyword ||= (keywords.key?('$defs') ? '$defs' : 'definitions')
    end

    def resources
      @resources ||= { :lexical => {}, :dynamic => {} }
    end

    def error(formatted_instance_location:, **options)
      if value == false && parent&.respond_to?(:false_schema_error)
        parent.false_schema_error(:formatted_instance_location => formatted_instance_location, **options)
      else
        "value at #{formatted_instance_location} does not match schema"
      end
    end

    def inspect
      "#<#{self.class.name} @value=#{@value.inspect} @parent=#{@parent.inspect} @keyword=#{@keyword.inspect}>"
    end

  private

    def parse
      @parsed = {}

      if value.is_a?(Hash) && value.key?('$schema')
        @parsed['$schema'] = SCHEMA_KEYWORD_CLASS.new(value.fetch('$schema'), self, '$schema')
      elsif root == self && !meta_schema
        SCHEMA_KEYWORD_CLASS.new(DEFAULT_SCHEMA, self, '$schema')
      end

      if value.is_a?(Hash) && value.key?('$vocabulary')
        @parsed['$vocabulary'] = VOCABULARY_KEYWORD_CLASS.new(value.fetch('$vocabulary'), self, '$vocabulary')
      elsif vocabulary
        VOCABULARY_KEYWORD_CLASS.new(vocabulary, self, '$vocabulary')
      end

      keywords = meta_schema.keywords
      exclusive_ref = value.is_a?(Hash) && value.key?('$ref') && keywords.fetch('$ref').exclusive?

      if root == self && (!value.is_a?(Hash) || !value.key?(meta_schema.id_keyword) || exclusive_ref)
        ID_KEYWORD_CLASS.new(base_uri, self, meta_schema.id_keyword)
      end

      if exclusive_ref
        @parsed['$ref'] = keywords.fetch('$ref').new(value.fetch('$ref'), self, '$ref')
        defs_keyword = meta_schema.defs_keyword
        if value.key?(defs_keyword) && keywords.key?(defs_keyword)
          @parsed[defs_keyword] = keywords.fetch(defs_keyword).new(value.fetch(defs_keyword), self, defs_keyword)
        end
      elsif value.is_a?(Hash)
        keyword_order = meta_schema.keyword_order
        last = keywords.size

        value.sort do |(keyword_a, _value_a), (keyword_b, _value_b)|
          keyword_order.fetch(keyword_a, last) <=> keyword_order.fetch(keyword_b, last)
        end.each do |keyword, value|
          @parsed[keyword] ||= keywords.fetch(keyword, UNKNOWN_KEYWORD_CLASS).new(value, self, keyword)
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

    def resolve_enumerators!(output)
      case output
      when Hash
        output.transform_values! { |value| resolve_enumerators!(value) }
      when Enumerator
        output.map { |value| resolve_enumerators!(value) }
      else
        output
      end
    end
  end
end
