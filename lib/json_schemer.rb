# frozen_string_literal: true

require "json_schemer/version"
require "time"
require "uri"
require "ipaddr"
require "hana"
require "addressable"

module JsonSchemer
  class << self
    BOOLEANS = Set[true, false].freeze
    # this is no good
    EMAIL_REGEX = /\A[^@\s]+@([\p{L}\d-]+\.)+[\p{L}\d\-]{2,}\z/i.freeze
    LABEL_REGEX_STRING = '\p{L}([\p{L}\p{N}\-]*[\p{L}\p{N}])?'
    HOSTNAME_REGEX = /\A(#{LABEL_REGEX_STRING}\.)*#{LABEL_REGEX_STRING}\z/i.freeze
    URI_PARSER = URI::RFC3986_Parser.new.freeze
    JSON_POINTER_REGEX_STRING = '(\/([^~\/]|~[01])*)*'
    JSON_POINTER_REGEX = /\A#{JSON_POINTER_REGEX_STRING}\z/.freeze
    RELATIVE_JSON_POINTER_REGEX = /\A(0|[1-9]\d*)(#|#{JSON_POINTER_REGEX_STRING})?\z/.freeze

    def valid?(schema, data, root = schema)
      validate(schema, data, '#', root).none?
    end

    def validate(schema, data, pointer = '#', root = schema)
      return enum_for(:validate, schema, data, pointer, root) unless block_given?

      return if schema == true
      if schema == false
        yield error(schema, data, pointer, 'schema')
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

      if ref
        _ref_address, ref_pointer = ref.split('#')
        ref_schema = Hana::Pointer.new(URI.unescape(ref_pointer || '')).eval(root)
        if ref_schema == schema
          yield error(schema, data, pointer, 'ref')
        elsif !ref_schema.nil?
          validate(ref_schema, data, pointer, root, &Proc.new)
        end
        return
      end

      yield error(schema, data, pointer, 'enum') if enum && !enum.include?(data)
      yield error(schema, data, pointer, 'const') if schema.key?('const') && schema['const'] != data

      yield error(schema, data, pointer, 'allOf') if all_of && !all_of.all? { |subschema| valid?(subschema, data, root) }
      yield error(schema, data, pointer, 'anyOf') if any_of && !any_of.any? { |subschema| valid?(subschema, data, root) }
      yield error(schema, data, pointer, 'oneOf') if one_of && !one_of.one? { |subschema| valid?(subschema, data, root) }
      yield error(schema, data, pointer, 'not') if !not_schema.nil? && valid?(not_schema, data, root)

      if if_schema && valid?(if_schema, data, root)
        yield error(schema, data, pointer, 'then') if !then_schema.nil? && !valid?(then_schema, data, root)
      elsif if_schema
        yield error(schema, data, pointer, 'else') if !else_schema.nil? && !valid?(else_schema, data, root)
      end

      case type
      when 'null'
        yield error(schema, data, pointer, 'null') unless data.nil?
      when 'boolean'
        yield error(schema, data, pointer, 'boolean') unless BOOLEANS.include?(data)
      when 'number'
        validate_number(schema, data, pointer, &Proc.new)
      when 'integer'
        validate_integer(schema, data, pointer, &Proc.new)
      when 'string'
        validate_string(schema, data, pointer, &Proc.new)
      when 'array'
        validate_array(schema, data, pointer, root, &Proc.new)
      when 'object'
        validate_object(schema, data, pointer, root, &Proc.new)
      when Array
        if type.all? { |subtype| !valid?(schema.merge('type' => subtype), data, root) }
          yield error(schema, data, pointer, 'type')
        end
      else
        case data
        when Integer
          validate_integer(schema, data, pointer, &Proc.new)
        when Numeric
          validate_number(schema, data, pointer, &Proc.new)
        when String
          validate_string(schema, data, pointer, &Proc.new)
        when Array
          validate_array(schema, data, pointer, root, &Proc.new)
        when Hash
          validate_object(schema, data, pointer, root, &Proc.new)
        end
      end
    end

  private

    def error(schema, data, pointer, type)
      {
        'schema' => schema,
        'data' => data,
        'pointer' => pointer,
        'type' => type,
      }
    end

    def validate_numeric(schema, data, pointer)
      multiple_of = schema['multipleOf']
      maximum = schema['maximum']
      exclusive_maximum = schema['exclusiveMaximum']
      minimum = schema['minimum']
      exclusive_minimum = schema['exclusiveMinimum']

      yield error(schema, data, pointer, 'maximum') if maximum && data > maximum
      yield error(schema, data, pointer, 'exclusiveMaximum') if exclusive_maximum && data >= exclusive_maximum
      yield error(schema, data, pointer, 'minimum') if minimum && data < minimum
      yield error(schema, data, pointer, 'exclusiveMinimum') if exclusive_minimum && data <= exclusive_minimum

      if multiple_of
        quotient = data / multiple_of.to_f
        yield error(schema, data, pointer, 'multipleOf') unless quotient.floor == quotient
      end
    end

    def validate_number(schema, data, pointer)
      unless data.is_a?(Numeric)
        yield error(schema, data, pointer, 'number')
        return
      end

      validate_numeric(schema, data, pointer, &Proc.new)
    end

    def validate_integer(schema, data, pointer)
      if !data.is_a?(Numeric) || (!data.is_a?(Integer) && data.floor != data)
        yield error(schema, data, pointer, 'integer')
        return
      end

      validate_numeric(schema, data, pointer, &Proc.new)
    end

    def validate_string(schema, data, pointer)
      unless data.is_a?(String)
        yield error(schema, data, pointer, 'string')
        return
      end

      max_length = schema['maxLength']
      min_length = schema['minLength']
      pattern = schema['pattern']
      format = schema['format']

      yield error(schema, data, pointer, 'maxLength') if max_length && data.size > max_length
      yield error(schema, data, pointer, 'minLength') if min_length && data.size < min_length
      yield error(schema, data, pointer, 'pattern') if pattern && !Regexp.new(pattern).match?(data)

      validate_string_format(schema, data, pointer, format, &Proc.new) if format
    end

    def validate_string_format(schema, data, pointer, format)
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
        valid_uri?(data, ascii_only: true, absolute_only: true)
      when 'uri-reference'
        valid_uri?(data, ascii_only: true, absolute_only: false)
      when 'iri'
        valid_uri?(data, ascii_only: false, absolute_only: true)
      when 'iri-reference'
        valid_uri?(data, ascii_only: false, absolute_only: false)
      when 'uri-template'
        raise NotImplementedError
      when 'json-pointer'
        JSON_POINTER_REGEX.match?(data)
      when 'relative-json-pointer'
        RELATIVE_JSON_POINTER_REGEX.match?(data)
      when 'regex'
        valid_regex?(data)
      end
      yield error(schema, data, pointer, 'format') unless valid
    end

    def validate_array(schema, data, pointer, root, &block)
      unless data.is_a?(Array)
        yield error(schema, data, pointer, 'array')
        return
      end

      items = schema['items']
      additional_items = schema['additionalItems']
      max_items = schema['maxItems']
      min_items = schema['minItems']
      unique_items = schema['uniqueItems']
      contains = schema['contains']

      yield error(schema, data, pointer, 'maxItems') if max_items && data.size > max_items
      yield error(schema, data, pointer, 'minItems') if min_items && data.size < min_items
      yield error(schema, data, pointer, 'uniqueItems') if unique_items && data.size != data.uniq.size
      yield error(schema, data, pointer, 'contains') if !contains.nil? && data.all? { |item| !valid?(contains, item, root) }

      if items.is_a?(Array)
        data.each_with_index do |item, index|
          if index < items.size
            validate(items[index], item, "#{pointer}/#{index}", root, &block)
          elsif !additional_items.nil?
            validate(additional_items, item, "#{pointer}/#{index}", root, &block)
          else
            break
          end
        end
      elsif !items.nil?
        data.each_with_index do |item, index|
          validate(items, item, "#{pointer}/#{index}", root, &block)
        end
      end
    end

    def validate_object(schema, data, pointer, root, &block)
      unless data.is_a?(Hash)
        yield error(schema, data, pointer, 'object')
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
          validate(subschema, data, pointer, root, &block)
        end
      end

      yield error(schema, data, pointer, 'maxProperties') if max_properties && data.size > max_properties
      yield error(schema, data, pointer, 'minProperties') if min_properties && data.size < min_properties
      yield error(schema, data, pointer, 'required') if required && required.any? { |key| !data.key?(key) }

      regex_pattern_properties = nil
      data.each do |key, value|
        validate(property_names, key, pointer, root, &block) unless property_names.nil?

        matched_key = false

        if properties && properties.key?(key)
          validate(properties[key], value, "#{pointer}/#{key}", root, &block)
          matched_key = true
        end

        if pattern_properties
          regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
            [Regexp.new(pattern), property_schema]
          end
          regex_pattern_properties.each do |regex, property_schema|
            if regex.match?(key)
              validate(property_schema, value, "#{pointer}/#{key}", root, &block)
              matched_key = true
            end
          end
        end

        next if matched_key

        validate(additional_properties, value, "#{pointer}/#{key}", root, &block) unless additional_properties.nil?
      end
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

    def valid_uri?(data, ascii_only:, absolute_only:)
      return false if ascii_only && !data.ascii_only?
      URI_PARSER.parse(data) if ascii_only
      uri = Addressable::URI.parse(data)
      absolute_only ? uri.absolute? : true
    rescue URI::InvalidURIError, Addressable::URI::InvalidURIError
      false
    end

    def valid_regex?(data)
      Regexp.new(data)
      true
    rescue RegexpError
      false
    end
  end
end
