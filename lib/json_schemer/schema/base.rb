# frozen_string_literal: true

module JSONSchemer
  module Schema
    class Base
      include Format

      Instance = Struct.new(:data, :data_pointer, :schema, :schema_pointer, :parent_uri) do
        def merge(
          data: self.data,
          data_pointer: self.data_pointer,
          schema: self.schema,
          schema_pointer: self.schema_pointer,
          parent_uri: self.parent_uri
        )
          self.class.new(data, data_pointer, schema, schema_pointer, parent_uri)
        end
      end

      ID_KEYWORD = '$id'
      DEFAULT_REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
      NET_HTTP_REF_RESOLVER = proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
      BOOLEANS = Set[true, false].freeze

      RUBY_REGEX_ANCHORS_TO_ECMA_262 = {
        :bos => 'A',
        :eos => 'z',
        :bol => '\A',
        :eol => '\z'
      }.freeze

      def initialize(
        schema,
        format: true,
        formats: nil,
        keywords: nil,
        ref_resolver: DEFAULT_REF_RESOLVER
      )
        raise InvalidSymbolKey, 'schemas must use string keys' if schema.is_a?(Hash) && !schema.first.first.is_a?(String)
        @root = schema
        @format = format
        @formats = formats
        @keywords = keywords
        @ref_resolver = ref_resolver == 'net/http' ? CachedRefResolver.new(&NET_HTTP_REF_RESOLVER) : ref_resolver
      end

      def valid?(data)
        valid_instance?(Instance.new(data, '', root, '', nil))
      end

      def validate(data)
        validate_instance(Instance.new(data, '', root, '', nil))
      end

    protected

      def discriminate(instance, field_name)
        instance.schema[field_name]
      end

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
        discriminator = schema['discriminator']

        all_of = schema['allOf']
        all_of = discriminate(all_of, discriminator, instance.data) if all_of && discriminator
        if all_of&.empty? && discriminator
          yield error(instance, 'discriminator')
          return
        end

        any_of = schema['anyOf']
        any_of = discriminate(any_of, discriminator, instance.data) if any_of && discriminator
        if any_of&.empty? && discriminator
          yield error(instance, 'discriminator')
          return
        end

        one_of = schema['oneOf']
        one_of = discriminate(one_of, discriminator, instance.data) if one_of && discriminator
        if one_of&.empty? && discriminator
          yield error(instance, 'discriminator')
          return
        end

        not_schema = schema['not']
        if_schema = schema['if']
        then_schema = schema['then']
        else_schema = schema['else']
        format = schema['format']
        ref = schema['$ref']
        id = schema[id_keyword]

        instance.parent_uri = join_uri(instance.parent_uri, id)

        if ref
          validate_ref(instance, ref, &block)
          return
        end

        if format? && custom_format?(format)
          validate_custom_format(instance, formats.fetch(format), &block)
        end

        if keywords
          keywords.each do |keyword, callable|
            if schema.key?(keyword)
              result = callable.call(data, schema, instance.pointer)
              if result.is_a?(Array)
                result.each(&block)
              elsif !result
                yield error(instance, keyword)
              end
            end
          end
        end

        data = instance.data

        yield error(instance, 'enum') if enum && !enum.include?(data)
        yield error(instance, 'const') if schema.key?('const') && schema['const'] != data

        if all_of
          all_of.each_with_index do |subschema, index|
            validate_instance(instance.merge(schema: subschema, schema_pointer: "#{instance.schema_pointer}/allOf/#{index}"), &block)
          end
        end

        if any_of
          subschemas = any_of.lazy.with_index.map do |subschema, index|
            validate_instance(instance.merge(schema: subschema, schema_pointer: "#{instance.schema_pointer}/anyOf/#{index}"))
          end
          subschemas.each { |subschema| subschema.each(&block) } unless subschemas.any?(&:none?)
        end

        if one_of
          subschemas = one_of.map.with_index do |subschema, index|
            validate_instance(instance.merge(schema: subschema, schema_pointer: "#{instance.schema_pointer}/oneOf/#{index}"))
          end
          valid_subschema_count = subschemas.count(&:none?)
          if valid_subschema_count > 1
            yield error(instance, 'oneOf')
          elsif valid_subschema_count == 0
            subschemas.each { |subschema| subschema.each(&block) }
          end
        end

        unless not_schema.nil?
          subinstance = instance.merge(schema: not_schema, schema_pointer: "#{instance.schema_pointer}/not")
          yield error(subinstance, 'not') if valid_instance?(subinstance)
        end

        if if_schema && valid_instance?(instance.merge(schema: if_schema))
          validate_instance(instance.merge(schema: then_schema, schema_pointer: "#{instance.schema_pointer}/then"), &block) unless then_schema.nil?
        elsif if_schema
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

      attr_reader :root, :formats, :keywords, :ref_resolver

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

      def child(schema)
        JSONSchemer.schema(
          schema,
          format: format?,
          formats: formats,
          keywords: keywords,
          ref_resolver: ref_resolver
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
        ref_uri = join_uri(instance.parent_uri, ref)

        if valid_json_pointer?(ref_uri.fragment)
          ref_pointer = Hana::Pointer.new(URI.decode_www_form_component(ref_uri.fragment))
          if ref.start_with?('#')
            subinstance = instance.merge(
              schema: ref_pointer.eval(root),
              schema_pointer: ref_uri.fragment,
              parent_uri: pointer_uri(root, ref_pointer)
            )
            validate_instance(subinstance, &block)
          else
            ref_root = resolve_ref(ref_uri)
            ref_object = child(ref_root)
            subinstance = instance.merge(
              schema: ref_pointer.eval(ref_root),
              schema_pointer: ref_uri.fragment,
              parent_uri: pointer_uri(ref_root, ref_pointer)
            )
            ref_object.validate_instance(subinstance, &block)
          end
        elsif id = ids[ref_uri.to_s]
          subinstance = instance.merge(
            schema: id.fetch(:schema),
            schema_pointer: id.fetch(:pointer),
            parent_uri: ref_uri
          )
          validate_instance(subinstance, &block)
        else
          ref_root = resolve_ref(ref_uri)
          ref_object = child(ref_root)
          id = ref_object.ids[ref_uri.to_s] || { schema: ref_root, pointer: '' }
          subinstance = instance.merge(
            schema: id.fetch(:schema),
            schema_pointer: id.fetch(:pointer),
            parent_uri: ref_uri
          )
          ref_object.validate_instance(subinstance, &block)
        end
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
          quotient = data / multiple_of.to_f
          yield error(instance, 'multipleOf') unless quotient.floor == quotient
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
        yield error(instance, 'pattern') if pattern && ecma_262_regex(pattern) !~ data
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

        if dependencies
          dependencies.each do |key, value|
            next unless data.key?(key)
            subschema = value.is_a?(Array) ? { 'required' => value } : value
            subinstance = instance.merge(schema: subschema, schema_pointer: "#{instance.schema_pointer}/dependencies/#{key}")
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
              data_pointer: "#{instance.data_pointer}/#{key}",
              schema: properties[key],
              schema_pointer: "#{instance.schema_pointer}/properties/#{key}"
            )
            validate_instance(subinstance, &block)
            matched_key = true
          end

          if pattern_properties
            regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
              [pattern, ecma_262_regex(pattern), property_schema]
            end
            regex_pattern_properties.each do |pattern, regex, property_schema|
              if regex =~ key
                subinstance = instance.merge(
                  data: value,
                  data_pointer: "#{instance.data_pointer}/#{key}",
                  schema: property_schema,
                  schema_pointer: "#{instance.schema_pointer}/patternProperties/#{pattern}"
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
              data_pointer: "#{instance.data_pointer}/#{key}",
              schema: additional_properties,
              schema_pointer: "#{instance.schema_pointer}/additionalProperties"
            )
            validate_instance(subinstance, &block)
          end
        end
      end

      def safe_strict_decode64(data)
        begin
          Base64.strict_decode64(data)
        rescue ArgumentError => e
          raise e unless e.message == 'invalid base64'
          nil
        end
      end

      def ecma_262_regex(pattern)
        @ecma_262_regex ||= {}
        @ecma_262_regex[pattern] ||= Regexp.new(
          Regexp::Scanner.scan(pattern).map do |type, token, text|
            type == :anchor ? RUBY_REGEX_ANCHORS_TO_ECMA_262.fetch(token, text) : text
          end.join
        )
      end

      def join_uri(a, b)
        if a && b
          URI.join(a, b)
        elsif b
          URI.parse(b)
        else
          a
        end
      end

      def pointer_uri(schema, pointer)
        uri_parts = nil
        pointer.reduce(schema) do |obj, token|
          next obj.fetch(token.to_i) if obj.is_a?(Array)
          if obj_id = obj[id_keyword]
            uri_parts ||= []
            uri_parts << obj_id
          end
          obj.fetch(token)
        end
        uri_parts ? URI.join(*uri_parts) : nil
      end

      def resolve_ids(schema, ids = {}, parent_uri = nil, pointer = '')
        if schema.is_a?(Array)
          schema.each_with_index { |subschema, index| resolve_ids(subschema, ids, parent_uri, "#{pointer}/#{index}") }
        elsif schema.is_a?(Hash)
          id = schema[id_keyword]
          uri = join_uri(parent_uri, id)
          unless uri == parent_uri
            ids[uri.to_s] = {
              schema: schema,
              pointer: pointer
            }
          end
          if definitions = schema['definitions']
            definitions.each { |key, subschema| resolve_ids(subschema, ids, uri, "#{pointer}/definitions/#{key}") }
          end
        end
        ids
      end

      def resolve_ref(uri)
        ref_resolver.call(uri) || raise(InvalidRefResolution, uri.to_s)
      end
    end
  end
end
