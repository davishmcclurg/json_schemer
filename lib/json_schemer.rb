# frozen_string_literal: true

require "json_schemer/version"

require "base64"
require "ecma-re-validator"
require "hana"
require "ipaddr"
require "json"
require 'net/http'
require "rdf"
require "time"
require "uri"
require "uri_template"

module JsonSchemer
  class Resolver
    extend Forwardable

    def_delegators :ids, :fetch, :key?

    def self.join(a, b)
      if a && b
        URI.join(a, b)
      elsif b
        URI.parse(b)
      else
        a
      end
    end

    def initialize(schema)
      @schema = schema
    end

  private

    def ids
      @ids ||= resolve(@schema)
    end

    def resolve(schema, ids = {}, parent_uri = nil)
      if schema.is_a?(Array)
        schema.each { |subschema| resolve(subschema, ids, parent_uri) }
      elsif schema.is_a?(Hash)
        id = schema['$id']
        uri = self.class.join(parent_uri, id)
        ids[uri.to_s] = schema unless uri == parent_uri
        if definitions = schema['definitions']
          definitions.each_value { |subschema| resolve(subschema, ids, uri) }
        end
      end
      ids
    end
  end

  class Schema
    BOOLEANS = Set[true, false].freeze
    # this is no good
    EMAIL_REGEX = /\A[^@\s]+@([\p{L}\d-]+\.)+[\p{L}\d\-]{2,}\z/i.freeze
    LABEL_REGEX_STRING = '\p{L}([\p{L}\p{N}\-]*[\p{L}\p{N}])?'
    HOSTNAME_REGEX = /\A(#{LABEL_REGEX_STRING}\.)*#{LABEL_REGEX_STRING}\z/i.freeze
    JSON_POINTER_REGEX_STRING = '(\/([^~\/]|~[01])*)*'
    JSON_POINTER_REGEX = /\A#{JSON_POINTER_REGEX_STRING}\z/.freeze
    RELATIVE_JSON_POINTER_REGEX = /\A(0|[1-9]\d*)(#|#{JSON_POINTER_REGEX_STRING})?\z/.freeze

    def initialize(schema, resolver = nil)
      @root = schema
      @resolver = resolver || Resolver.new(schema)
    end

    def valid?(data, schema = root, pointer = '#', parent_uri = nil)
      validate(data, schema, pointer, parent_uri).none?
    end

    def validate(data, schema = root, pointer = '#', parent_uri = nil)
      return enum_for(:validate, data, schema, pointer, parent_uri) unless block_given?

      return if schema == true
      if schema == false
        yield error(data, schema, pointer, 'schema')
        return
      end

      return if schema.empty?

      type = schema['type']
      enum = schema['enum']
      all_of = schema['allOf']
      any_of = schema['anyOf']
      one_of = schema['oneOf']
      not_schema = schema['not']
      if_schema = schema['if']
      then_schema = schema['then']
      else_schema = schema['else']
      ref = schema['$ref']
      id = schema['$id']

      parent_uri = Resolver.join(parent_uri, id)

      if ref
        validate_ref(data, schema, pointer, parent_uri, ref, &Proc.new)
        return
      end

      yield error(data, schema, pointer, 'enum') if enum && !enum.include?(data)
      yield error(data, schema, pointer, 'const') if schema.key?('const') && schema['const'] != data

      yield error(data, schema, pointer, 'allOf') if all_of && !all_of.all? { |subschema| valid?(data, subschema, pointer, parent_uri) }
      yield error(data, schema, pointer, 'anyOf') if any_of && !any_of.any? { |subschema| valid?(data, subschema, pointer, parent_uri) }
      yield error(data, schema, pointer, 'oneOf') if one_of && !one_of.one? { |subschema| valid?(data, subschema, pointer, parent_uri) }
      yield error(data, schema, pointer, 'not') if !not_schema.nil? && valid?(data, not_schema, pointer, parent_uri)

      if if_schema && valid?(data, if_schema, pointer, parent_uri)
        yield error(data, schema, pointer, 'then') if !then_schema.nil? && !valid?(data, then_schema, pointer, parent_uri)
      elsif if_schema
        yield error(data, schema, pointer, 'else') if !else_schema.nil? && !valid?(data, else_schema, pointer, parent_uri)
      end

      case type
      when nil
        validate_class(data, schema, pointer, parent_uri, &Proc.new)
      when String
        validate_type(data, schema, pointer, parent_uri, type, &Proc.new)
      when Array
        if valid_type = type.find { |subtype| valid?(data, { 'type' => subtype }, pointer, parent_uri) }
          validate_type(data, schema, pointer, parent_uri, valid_type, &Proc.new)
        else
          yield error(data, schema, pointer, 'type')
        end
      end
    end

  private

    attr_reader :root, :resolver

    def error(data, schema, pointer, type)
      {
        'data' => data,
        'schema' => schema,
        'pointer' => pointer,
        'type' => type,
      }
    end

    def validate_class(data, schema, pointer, parent_uri)
      case data
      when Integer
        validate_integer(data, schema, pointer, &Proc.new)
      when Numeric
        validate_number(data, schema, pointer, &Proc.new)
      when String
        validate_string(data, schema, pointer, &Proc.new)
      when Array
        validate_array(data, schema, pointer, parent_uri, &Proc.new)
      when Hash
        validate_object(data, schema, pointer, parent_uri, &Proc.new)
      end
    end

    def validate_type(data, schema, pointer, parent_uri, type)
      case type
      when 'null'
        yield error(data, schema, pointer, 'null') unless data.nil?
      when 'boolean'
        yield error(data, schema, pointer, 'boolean') unless BOOLEANS.include?(data)
      when 'number'
        validate_number(data, schema, pointer, &Proc.new)
      when 'integer'
        validate_integer(data, schema, pointer, &Proc.new)
      when 'string'
        validate_string(data, schema, pointer, &Proc.new)
      when 'array'
        validate_array(data, schema, pointer, parent_uri, &Proc.new)
      when 'object'
        validate_object(data, schema, pointer, parent_uri, &Proc.new)
      end
    end

    def validate_ref(data, schema, pointer, parent_uri, ref)
      ref_uri = Resolver.join(parent_uri, ref)

      if valid_json_pointer?(ref_uri.fragment)
        ref_pointer = Hana::Pointer.new(URI.unescape(ref_uri.fragment || ''))
        if ref.start_with?('#')
          validate(data, ref_pointer.eval(root), pointer, pointer_uri(root, ref_pointer), &Proc.new)
        else
          ref_root = JSON.parse(Net::HTTP.get(ref_uri))
          ref_object = self.class.new(ref_root)
          ref_object.validate(data, ref_pointer.eval(ref_root), pointer, pointer_uri(ref_root, ref_pointer), &Proc.new)
        end
      elsif resolver.key?(ref_uri.to_s)
        validate(data, resolver.fetch(ref_uri.to_s), pointer, ref_uri, &Proc.new)
      else
        ref_root = JSON.parse(Net::HTTP.get(ref_uri))
        ref_resolver = Resolver.new(ref_root)
        ref_object = self.class.new(ref_root, ref_resolver)
        ref_object.validate(data, ref_resolver.fetch(ref_uri.to_s, ref_root), pointer, ref_uri, &Proc.new)
      end
    end

    def validate_numeric(data, schema, pointer)
      multiple_of = schema['multipleOf']
      maximum = schema['maximum']
      exclusive_maximum = schema['exclusiveMaximum']
      minimum = schema['minimum']
      exclusive_minimum = schema['exclusiveMinimum']

      yield error(data, schema, pointer, 'maximum') if maximum && data > maximum
      yield error(data, schema, pointer, 'exclusiveMaximum') if exclusive_maximum && data >= exclusive_maximum
      yield error(data, schema, pointer, 'minimum') if minimum && data < minimum
      yield error(data, schema, pointer, 'exclusiveMinimum') if exclusive_minimum && data <= exclusive_minimum

      if multiple_of
        quotient = data / multiple_of.to_f
        yield error(data, schema, pointer, 'multipleOf') unless quotient.floor == quotient
      end
    end

    def validate_number(data, schema, pointer)
      unless data.is_a?(Numeric)
        yield error(data, schema, pointer, 'number')
        return
      end

      validate_numeric(data, schema, pointer, &Proc.new)
    end

    def validate_integer(data, schema, pointer)
      if !data.is_a?(Numeric) || (!data.is_a?(Integer) && data.floor != data)
        yield error(data, schema, pointer, 'integer')
        return
      end

      validate_numeric(data, schema, pointer, &Proc.new)
    end

    def validate_string(data, schema, pointer)
      unless data.is_a?(String)
        yield error(data, schema, pointer, 'string')
        return
      end

      max_length = schema['maxLength']
      min_length = schema['minLength']
      pattern = schema['pattern']
      format = schema['format']
      content_encoding = schema['contentEncoding']
      content_media_type = schema['contentMediaType']

      yield error(data, schema, pointer, 'maxLength') if max_length && data.size > max_length
      yield error(data, schema, pointer, 'minLength') if min_length && data.size < min_length
      yield error(data, schema, pointer, 'pattern') if pattern && !Regexp.new(pattern).match?(data)

      validate_string_format(data, schema, pointer, format, &Proc.new) if format

      if content_encoding || content_media_type
        decoded_data = data

        if content_encoding
          decoded_data = case content_encoding.downcase
          when 'base64'
            safe_strict_decode64(data)
          else # '7bit', '8bit', 'binary', 'quoted-printable'
            raise NotImplementedError
          end
          yield error(data, schema, pointer, 'contentEncoding') unless decoded_data
        end

        if content_media_type && decoded_data
          case content_media_type.downcase
          when 'application/json'
            yield error(data, schema, pointer, 'contentMediaType') unless valid_json?(decoded_data)
          else
            raise NotImplementedError
          end
        end
      end
    end

    def validate_string_format(data, schema, pointer, format)
      valid = case format
      when 'date-time'
        valid_date_time?(data)
      when 'date'
        valid_date_time?("#{data}T04:05:06.123456789+07:00")
      when 'time'
        valid_date_time?("2001-02-03T#{data}")
      when 'email'
        data.ascii_only? && EMAIL_REGEX.match?(data)
      when 'idn-email'
        EMAIL_REGEX.match?(data)
      when 'hostname'
        data.ascii_only? && valid_hostname?(data)
      when 'idn-hostname'
        valid_hostname?(data)
      when 'ipv4'
        valid_ip?(data, :v4)
      when 'ipv6'
        valid_ip?(data, :v6)
      when 'uri'
        data.ascii_only? && RDF::URI::IRI.match?(data)
      when 'uri-reference'
        data.ascii_only? && (RDF::URI::IRI.match?(data) || RDF::URI::IRELATIVE_REF.match?(data))
      when 'iri'
        RDF::URI::IRI.match?(data)
      when 'iri-reference'
        RDF::URI::IRI.match?(data) || RDF::URI::IRELATIVE_REF.match?(data)
      when 'uri-template'
        valid_uri_template?(data)
      when 'json-pointer'
        valid_json_pointer?(data)
      when 'relative-json-pointer'
        RELATIVE_JSON_POINTER_REGEX.match?(data)
      when 'regex'
        EcmaReValidator.valid?(data)
      end
      yield error(data, schema, pointer, 'format') unless valid
    end

    def validate_array(data, schema, pointer, parent_uri, &block)
      unless data.is_a?(Array)
        yield error(data, schema, pointer, 'array')
        return
      end

      items = schema['items']
      additional_items = schema['additionalItems']
      max_items = schema['maxItems']
      min_items = schema['minItems']
      unique_items = schema['uniqueItems']
      contains = schema['contains']

      yield error(data, schema, pointer, 'maxItems') if max_items && data.size > max_items
      yield error(data, schema, pointer, 'minItems') if min_items && data.size < min_items
      yield error(data, schema, pointer, 'uniqueItems') if unique_items && data.size != data.uniq.size
      yield error(data, schema, pointer, 'contains') if !contains.nil? && data.all? { |item| !valid?(item, contains, pointer, parent_uri) }

      if items.is_a?(Array)
        data.each_with_index do |item, index|
          if index < items.size
            validate(item, items[index], "#{pointer}/#{index}", parent_uri, &block)
          elsif !additional_items.nil?
            validate(item, additional_items, "#{pointer}/#{index}", parent_uri, &block)
          else
            break
          end
        end
      elsif !items.nil?
        data.each_with_index do |item, index|
          validate(item, items, "#{pointer}/#{index}", parent_uri, &block)
        end
      end
    end

    def validate_object(data, schema, pointer, parent_uri, &block)
      unless data.is_a?(Hash)
        yield error(data, schema, pointer, 'object')
        return
      end

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
          validate(data, subschema, pointer, parent_uri, &block)
        end
      end

      yield error(data, schema, pointer, 'maxProperties') if max_properties && data.size > max_properties
      yield error(data, schema, pointer, 'minProperties') if min_properties && data.size < min_properties
      yield error(data, schema, pointer, 'required') if required && required.any? { |key| !data.key?(key) }

      regex_pattern_properties = nil
      data.each do |key, value|
        validate(key, property_names, pointer, parent_uri, &block) unless property_names.nil?

        matched_key = false

        if properties && properties.key?(key)
          validate(value, properties[key], "#{pointer}/#{key}", parent_uri, &block)
          matched_key = true
        end

        if pattern_properties
          regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
            [Regexp.new(pattern), property_schema]
          end
          regex_pattern_properties.each do |regex, property_schema|
            if regex.match?(key)
              validate(value, property_schema, "#{pointer}/#{key}", parent_uri, &block)
              matched_key = true
            end
          end
        end

        next if matched_key

        validate(value, additional_properties, "#{pointer}/#{key}", parent_uri, &block) unless additional_properties.nil?
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

    def valid_json?(data)
      JSON.parse(data)
      true
    rescue JSON::ParserError
      false
    end

    def valid_date_time?(data)
      DateTime.rfc3339(data)
      true
    rescue ArgumentError => e
      raise e unless e.message == 'invalid date'
      false
    end

    def valid_hostname?(data)
      HOSTNAME_REGEX.match?(data) && data.split('.').all? { |label| label.size <= 63 }
    end

    def valid_ip?(data, type)
      ip_address = IPAddr.new(data)
      type == :v4 ? ip_address.ipv4? : ip_address.ipv6?
    rescue IPAddr::InvalidAddressError
      false
    end

    def valid_uri_template?(data)
      URITemplate.new(data)
      true
    rescue URITemplate::Invalid
      false
    end

    def valid_json_pointer?(data)
      JSON_POINTER_REGEX.match?(data)
    end

    def pointer_uri(schema, pointer)
      uri_parts = nil
      pointer.reduce(schema) do |obj, token|
        next obj.fetch(token.to_i) if obj.is_a?(Array)
        if obj_id = obj['$id']
          uri_parts ||= []
          uri_parts << obj_id
        end
        obj.fetch(token)
      end
      uri_parts ? URI.join(*uri_parts) : nil
    end
  end
end
