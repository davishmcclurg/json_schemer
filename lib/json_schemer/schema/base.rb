# frozen_string_literal: true
module JSONSchemer
  module Schema
    class Base
      include Format

      Instance = Struct.new(:data, :data_pointer, :schema, :schema_pointer, :base_uri, :before_property_validation, :after_property_validation) do
        def merge(
          data: self.data,
          data_pointer: self.data_pointer,
          schema: self.schema,
          schema_pointer: self.schema_pointer,
          base_uri: self.base_uri,
          before_property_validation: self.before_property_validation,
          after_property_validation: self.after_property_validation
        )
          self.class.new(data, data_pointer, schema, schema_pointer, base_uri, before_property_validation, after_property_validation)
        end
      end

      ID_KEYWORD = '$id'
      DEFAULT_REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
      NET_HTTP_REF_RESOLVER = proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
      RUBY_REGEXP_RESOLVER = proc { |pattern| Regexp.new(pattern) }
      ECMA_REGEXP_RESOLVER = proc { |pattern| Regexp.new(EcmaRegexp.ruby_equivalent(pattern)) }
      BOOLEANS = Set[true, false].freeze

      INSERT_DEFAULT_PROPERTY = proc do |data, property, property_schema, _parent|
        if !data.key?(property) && property_schema.is_a?(Hash) && property_schema.key?('default')
          data[property] = property_schema.fetch('default').clone
        end
      end

      JSON_POINTER_TOKEN_ESCAPE_CHARS = { '~' => '~0', '/' => '~1' }
      JSON_POINTER_TOKEN_ESCAPE_REGEX = Regexp.union(JSON_POINTER_TOKEN_ESCAPE_CHARS.keys)

      class << self
        def draft_name
          name.split('::').last.downcase
        end

        def meta_schema
          @meta_schema ||= JSON.parse(Pathname.new(__dir__).join("#{draft_name}.json").read).freeze
        end

        def meta_schemer
          @meta_schemer ||= JSONSchemer.schema(meta_schema)
        end
      end

      def initialize(
        schema,
        base_uri: nil,
        format: true,
        insert_property_defaults: false,
        before_property_validation: nil,
        after_property_validation: nil,
        formats: nil,
        keywords: nil,
        ref_resolver: DEFAULT_REF_RESOLVER,
        regexp_resolver: 'ruby'
      )
        raise InvalidSymbolKey, 'schemas must use string keys' if schema.is_a?(Hash) && !schema.empty? && !schema.first.first.is_a?(String)
        @root = schema
        @base_uri = base_uri
        @format = format
        @before_property_validation = [*before_property_validation]
        @before_property_validation.unshift(INSERT_DEFAULT_PROPERTY) if insert_property_defaults
        @after_property_validation = [*after_property_validation]
        @formats = formats
        @keywords = keywords
        @ref_resolver = ref_resolver == 'net/http' ? CachedResolver.new(&NET_HTTP_REF_RESOLVER) : ref_resolver
        @regexp_resolver = case regexp_resolver
        when 'ecma'
          CachedResolver.new(&ECMA_REGEXP_RESOLVER)
        when 'ruby'
          CachedResolver.new(&RUBY_REGEXP_RESOLVER)
        else
          regexp_resolver
        end
      end

      def valid?(data)
        valid_instance?(Instance.new(data, '', root, '', @base_uri, @before_property_validation, @after_property_validation))
      end

      def validate(data)
        validate_instance(Instance.new(data, '', root, '', @base_uri, @before_property_validation, @after_property_validation))
      end

      def valid_schema?
        self.class.meta_schemer.valid?(root)
      end

      def validate_schema
        self.class.meta_schemer.validate(root)
      end

    protected

      attr_reader :root

      def valid_instance?(instance)
        validate_instance(instance).none?
      end

      def validate_instance(instance, &block)
        return enum_for(:validate_instance, instance) unless block_given?

        schema = instance.schema

        if schema == false
          yield error(instance, 'schema')
          return
        end

        return if schema == true || schema.empty?

        type = schema['type']
        enum = schema['enum']
        all_of = schema['allOf']
        any_of = schema['anyOf']
        one_of = schema['oneOf']
        not_schema = schema['not']
        if_schema = schema['if']
        then_schema = schema['then']
        else_schema = schema['else']
        format = schema['format']
        ref = schema['$ref']
        id = schema[id_keyword]

        if ref
          validate_ref(instance, ref, &block)
          return
        end

        instance.base_uri = join_uri(instance.base_uri, id)

        if format? && custom_format?(format)
          validate_custom_format(instance, formats.fetch(format), &block)
        end

        data = instance.data

        if keywords
          keywords.each do |keyword, callable|
            if schema.key?(keyword)
              result = callable.call(data, schema, instance.data_pointer)
              if result.is_a?(Array)
                result.each(&block)
              elsif !result
                yield error(instance, keyword)
              end
            end
          end
        end

        yield error(instance, 'enum') if enum && !enum.include?(data)
        yield error(instance, 'const') if schema.key?('const') && schema['const'] != data

        if all_of
          all_of.each_with_index do |subschema, index|
            subinstance = instance.merge(
              schema: subschema,
              schema_pointer: "#{instance.schema_pointer}/allOf/#{index}",
              before_property_validation: false,
              after_property_validation: false
            )
            validate_instance(subinstance, &block)
          end
        end

        if any_of
          subschemas = any_of.lazy.with_index.map do |subschema, index|
            subinstance = instance.merge(
              schema: subschema,
              schema_pointer: "#{instance.schema_pointer}/anyOf/#{index}",
              before_property_validation: false,
              after_property_validation: false
            )
            validate_instance(subinstance)
          end
          subschemas.each { |subschema| subschema.each(&block) } unless subschemas.any?(&:none?)
        end

        if one_of
          subschemas = one_of.map.with_index do |subschema, index|
            subinstance = instance.merge(
              schema: subschema,
              schema_pointer: "#{instance.schema_pointer}/oneOf/#{index}",
              before_property_validation: false,
              after_property_validation: false
            )
            validate_instance(subinstance)
          end
          valid_subschema_count = subschemas.count(&:none?)
          if valid_subschema_count > 1
            yield error(instance, 'oneOf')
          elsif valid_subschema_count == 0
            subschemas.each { |subschema| subschema.each(&block) }
          end
        end

        unless not_schema.nil?
          subinstance = instance.merge(
            schema: not_schema,
            schema_pointer: "#{instance.schema_pointer}/not",
            before_property_validation: false,
            after_property_validation: false
          )
          yield error(subinstance, 'not') if valid_instance?(subinstance)
        end

        if if_schema && valid_instance?(instance.merge(schema: if_schema, before_property_validation: false, after_property_validation: false))
          validate_instance(instance.merge(schema: then_schema, schema_pointer: "#{instance.schema_pointer}/then"), &block) unless then_schema.nil?
        elsif schema.key?('if')
          validate_instance(instance.merge(schema: else_schema, schema_pointer: "#{instance.schema_pointer}/else"), &block) unless else_schema.nil?
        end

        case type
        when nil
          validate_class(instance, &block)
        when String
          validate_type(instance, type, &block)
        when Array
          if valid_type = type.find { |subtype| valid_instance?(instance.merge(schema: { 'type' => subtype })) }
            validate_type(instance, valid_type, &block)
          else
            yield error(instance, 'type')
          end
        end
      end

      def ids
        @ids ||= resolve_ids(root)
      end

    private

      attr_reader :formats, :keywords, :ref_resolver, :regexp_resolver

      def id_keyword
        ID_KEYWORD
      end

      def format?
        !!@format
      end

      def custom_format?(format)
        !!(formats && formats.key?(format))
      end

      def spec_format?(format)
        !custom_format?(format) && supported_format?(format)
      end

      def child(schema, base_uri:)
        JSONSchemer.schema(
          schema,
          default_schema_class: self.class,
          base_uri: base_uri,
          format: format?,
          formats: formats,
          keywords: keywords,
          ref_resolver: ref_resolver,
          regexp_resolver: regexp_resolver
        )
      end

      def error(instance, type, details = nil)
        error = {
          'data' => instance.data,
          'data_pointer' => instance.data_pointer,
          'schema' => instance.schema,
          'schema_pointer' => instance.schema_pointer,
          'root_schema' => root,
          'type' => type,
        }
        error['details'] = details if details
        error
      end

      def validate_class(instance, &block)
        case instance.data
        when Integer
          validate_integer(instance, &block)
        when Numeric
          validate_number(instance, &block)
        when String
          validate_string(instance, &block)
        when Array
          validate_array(instance, &block)
        when Hash
          validate_object(instance, &block)
        end
      end

      def validate_type(instance, type, &block)
        case type
        when 'null'
          yield error(instance, 'null') unless instance.data.nil?
        when 'boolean'
          yield error(instance, 'boolean') unless BOOLEANS.include?(instance.data)
        when 'number'
          validate_number(instance, &block)
        when 'integer'
          validate_integer(instance, &block)
        when 'string'
          validate_string(instance, &block)
        when 'array'
          validate_array(instance, &block)
        when 'object'
          validate_object(instance, &block)
        end
      end

      def validate_ref(instance, ref, &block)
        ref_uri = join_uri(instance.base_uri, ref)

        ref_uri_pointer = ''
        if valid_json_pointer?(ref_uri.fragment)
          ref_uri_pointer = ref_uri.fragment
          ref_uri.fragment = nil
        end

        ref_object = if ids.key?(ref_uri) || ref_uri.to_s.empty? || ref_uri.to_s == @base_uri.to_s
          self
        else
          child(resolve_ref(ref_uri), base_uri: ref_uri)
        end

        ref_schema, ref_schema_pointer, ref_parent_base_uri = ref_object.ids[ref_uri] || [ref_object.root, '', ref_uri]

        ref_uri_pointer_parts = Hana::Pointer.parse(URI.decode_www_form_component(ref_uri_pointer))
        schema, base_uri = ref_uri_pointer_parts.reduce([ref_schema, ref_parent_base_uri]) do |(obj, uri), token|
          if obj.is_a?(Array)
            [obj.fetch(token.to_i), uri]
          else
            [obj.fetch(token), join_uri(uri, obj[id_keyword])]
          end
        end

        subinstance = instance.merge(
          schema: schema,
          schema_pointer: "#{ref_schema_pointer}#{ref_uri_pointer}",
          base_uri: base_uri
        )

        ref_object.validate_instance(subinstance, &block)
      end

      def validate_custom_format(instance, custom_format)
        yield error(instance, 'format') if custom_format != false && !custom_format.call(instance.data, instance.schema)
      end

      def validate_exclusive_maximum(instance, exclusive_maximum, maximum)
        yield error(instance, 'exclusiveMaximum') if instance.data >= exclusive_maximum
      end

      def validate_exclusive_minimum(instance, exclusive_minimum, minimum)
        yield error(instance, 'exclusiveMinimum') if instance.data <= exclusive_minimum
      end

      def validate_numeric(instance, &block)
        schema = instance.schema
        data = instance.data

        multiple_of = schema['multipleOf']
        maximum = schema['maximum']
        exclusive_maximum = schema['exclusiveMaximum']
        minimum = schema['minimum']
        exclusive_minimum = schema['exclusiveMinimum']

        yield error(instance, 'maximum') if maximum && data > maximum
        yield error(instance, 'minimum') if minimum && data < minimum

        validate_exclusive_maximum(instance, exclusive_maximum, maximum, &block) if exclusive_maximum
        validate_exclusive_minimum(instance, exclusive_minimum, minimum, &block) if exclusive_minimum

        if multiple_of
          yield error(instance, 'multipleOf') unless BigDecimal(data.to_s).modulo(multiple_of).zero?
        end
      end

      def validate_number(instance, &block)
        unless instance.data.is_a?(Numeric)
          yield error(instance, 'number')
          return
        end

        validate_numeric(instance, &block)
      end

      def validate_integer(instance, &block)
        data = instance.data

        if !data.is_a?(Numeric) || (!data.is_a?(Integer) && data.floor != data)
          yield error(instance, 'integer')
          return
        end

        validate_numeric(instance, &block)
      end

      def validate_string(instance, &block)
        data = instance.data

        unless data.is_a?(String)
          yield error(instance, 'string')
          return
        end

        schema = instance.schema

        max_length = schema['maxLength']
        min_length = schema['minLength']
        pattern = schema['pattern']
        format = schema['format']
        content_encoding = schema['contentEncoding']
        content_media_type = schema['contentMediaType']

        yield error(instance, 'maxLength') if max_length && data.size > max_length
        yield error(instance, 'minLength') if min_length && data.size < min_length
        yield error(instance, 'pattern') if pattern && !resolve_regexp(pattern).match?(data)
        yield error(instance, 'format') if format? && spec_format?(format) && !valid_spec_format?(data, format)

        if content_encoding || content_media_type
          decoded_data = data

          if content_encoding
            decoded_data = case content_encoding.downcase
            when 'base64'
              safe_strict_decode64(data)
            else # '7bit', '8bit', 'binary', 'quoted-printable'
              raise NotImplementedError
            end
            yield error(instance, 'contentEncoding') unless decoded_data
          end

          if content_media_type && decoded_data
            case content_media_type.downcase
            when 'application/json'
              yield error(instance, 'contentMediaType') unless valid_json?(decoded_data)
            else
              raise NotImplementedError
            end
          end
        end
      end

      def validate_array(instance, &block)
        data = instance.data

        unless data.is_a?(Array)
          yield error(instance, 'array')
          return
        end

        schema = instance.schema

        items = schema['items']
        additional_items = schema['additionalItems']
        max_items = schema['maxItems']
        min_items = schema['minItems']
        unique_items = schema['uniqueItems']
        contains = schema['contains']

        yield error(instance, 'maxItems') if max_items && data.size > max_items
        yield error(instance, 'minItems') if min_items && data.size < min_items
        yield error(instance, 'uniqueItems') if unique_items && data.size != data.uniq.size
        yield error(instance, 'contains') if !contains.nil? && data.all? { |item| !valid_instance?(instance.merge(data: item, schema: contains)) }

        if items.is_a?(Array)
          data.each_with_index do |item, index|
            if index < items.size
              subinstance = instance.merge(
                data: item,
                data_pointer: "#{instance.data_pointer}/#{index}",
                schema: items[index],
                schema_pointer: "#{instance.schema_pointer}/items/#{index}"
              )
              validate_instance(subinstance, &block)
            elsif !additional_items.nil?
              subinstance = instance.merge(
                data: item,
                data_pointer: "#{instance.data_pointer}/#{index}",
                schema: additional_items,
                schema_pointer: "#{instance.schema_pointer}/additionalItems"
              )
              validate_instance(subinstance, &block)
            else
              break
            end
          end
        elsif !items.nil?
          data.each_with_index do |item, index|
            subinstance = instance.merge(
              data: item,
              data_pointer: "#{instance.data_pointer}/#{index}",
              schema: items,
              schema_pointer: "#{instance.schema_pointer}/items"
            )
            validate_instance(subinstance, &block)
          end
        end
      end

      def validate_object(instance, &block)
        data = instance.data

        unless data.is_a?(Hash)
          yield error(instance, 'object')
          return
        end

        schema = instance.schema

        max_properties = schema['maxProperties']
        min_properties = schema['minProperties']
        required = schema['required']
        properties = schema['properties']
        pattern_properties = schema['patternProperties']
        additional_properties = schema['additionalProperties']
        dependencies = schema['dependencies']
        property_names = schema['propertyNames']

        if instance.before_property_validation && properties
          properties.each do |property, property_schema|
            instance.before_property_validation.each do |hook|
              hook.call(data, property, property_schema, schema)
            end
          end
        end

        if dependencies
          dependencies.each do |key, value|
            next unless data.key?(key)
            subschema = value.is_a?(Array) ? { 'required' => value } : value
            escaped_key = escape_json_pointer_token(key)
            subinstance = instance.merge(schema: subschema, schema_pointer: "#{instance.schema_pointer}/dependencies/#{escaped_key}")
            validate_instance(subinstance, &block)
          end
        end

        yield error(instance, 'maxProperties') if max_properties && data.size > max_properties
        yield error(instance, 'minProperties') if min_properties && data.size < min_properties
        if required
          missing_keys = required - data.keys
          yield error(instance, 'required', 'missing_keys' => missing_keys) if missing_keys.any?
        end

        regex_pattern_properties = nil
        data.each do |key, value|
          escaped_key = escape_json_pointer_token(key)

          unless property_names.nil?
            subinstance = instance.merge(
              data: key,
              schema: property_names,
              schema_pointer: "#{instance.schema_pointer}/propertyNames"
            )
            validate_instance(subinstance, &block)
          end

          matched_key = false

          if properties && properties.key?(key)
            subinstance = instance.merge(
              data: value,
              data_pointer: "#{instance.data_pointer}/#{escaped_key}",
              schema: properties[key],
              schema_pointer: "#{instance.schema_pointer}/properties/#{escaped_key}"
            )
            validate_instance(subinstance, &block)
            matched_key = true
          end

          if pattern_properties
            regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
              [pattern, resolve_regexp(pattern), property_schema]
            end
            regex_pattern_properties.each do |pattern, regex, property_schema|
              escaped_pattern = escape_json_pointer_token(pattern)
              if regex.match?(key)
                subinstance = instance.merge(
                  data: value,
                  data_pointer: "#{instance.data_pointer}/#{escaped_key}",
                  schema: property_schema,
                  schema_pointer: "#{instance.schema_pointer}/patternProperties/#{escaped_pattern}"
                )
                validate_instance(subinstance, &block)
                matched_key = true
              end
            end
          end

          next if matched_key

          unless additional_properties.nil?
            subinstance = instance.merge(
              data: value,
              data_pointer: "#{instance.data_pointer}/#{escaped_key}",
              schema: additional_properties,
              schema_pointer: "#{instance.schema_pointer}/additionalProperties"
            )
            validate_instance(subinstance, &block)
          end
        end

        if instance.after_property_validation && properties
          properties.each do |property, property_schema|
            instance.after_property_validation.each do |hook|
              hook.call(data, property, property_schema, schema)
            end
          end
        end
      end

      def safe_strict_decode64(data)
        Base64.strict_decode64(data)
      rescue ArgumentError
        nil
      end

      def escape_json_pointer_token(token)
        token.gsub(JSON_POINTER_TOKEN_ESCAPE_REGEX, JSON_POINTER_TOKEN_ESCAPE_CHARS)
      end

      def join_uri(a, b)
        b = URI.parse(b) if b
        uri = if a && b && a.relative? && b.relative?
          b
        elsif a && b
          URI.join(a, b)
        elsif b
          b
        else
          a
        end
        uri.fragment = nil if uri.is_a?(URI) && uri.fragment == ''
        uri
      end

      def resolve_ids(schema, ids = {}, base_uri = @base_uri, pointer = '')
        if schema.is_a?(Array)
          schema.each_with_index { |subschema, index| resolve_ids(subschema, ids, base_uri, "#{pointer}/#{index}") }
        elsif schema.is_a?(Hash)
          if schema.key?(id_keyword)
            parent_base_uri = base_uri
            base_uri = join_uri(base_uri, schema[id_keyword])
            ids[base_uri] ||= [schema, pointer, parent_base_uri]
          end
          schema.each do |key, value|
            case key
            when 'items', 'allOf', 'anyOf', 'oneOf', 'additionalItems', 'contains', 'additionalProperties', 'propertyNames', 'if', 'then', 'else', 'not'
              resolve_ids(value, ids, base_uri, "#{pointer}/#{key}")
            when 'properties', 'patternProperties', 'definitions', 'dependencies'
              value.each do |subkey, subvalue|
                resolve_ids(subvalue, ids, base_uri, "#{pointer}/#{key}/#{subkey}")
              end
            end
          end
        end
        ids
      end

      def resolve_ref(uri)
        ref_resolver.call(uri) || raise(InvalidRefResolution, uri.to_s)
      end

      def resolve_regexp(pattern)
        regexp_resolver.call(pattern) || raise(InvalidRegexpResolution, pattern)
      end
    end
  end
end
