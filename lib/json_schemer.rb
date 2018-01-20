# frozen_string_literal: true

require "json_schemer/version"
require "time"
require "uri"
require "hana"

module JsonSchemer
  class << self
    BOOLEANS = Set[true, false].freeze
    # this is no good
    EMAIL_REGEX = /\A[^@\s]+@([\p{L}\d-]+\.)+[\p{L}\d\-]{2,}\z/ix.freeze

    def valid?(schema, data, root = schema)
      !validate(schema, data, root).first
    end

    def validate(schema, data, root = schema)
      return enum_for(:validate, schema, data, root) unless block_given?

      return if schema == true
      if schema == false
        yield error(schema, data, nil, 'schema')
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

      yield error(schema, data, nil, 'enum') if enum && !enum.include?(data)
      yield error(schema, data, nil, 'const') if schema.key?('const') && schema['const'] != data

      yield error(schema, data, nil, 'allOf') if all_of && !all_of.all? { |subschema| valid?(subschema, data, root) }
      yield error(schema, data, nil, 'anyOf') if any_of && !any_of.any? { |subschema| valid?(subschema, data, root) }
      yield error(schema, data, nil, 'oneOf') if one_of && one_of.count { |subschema| valid?(subschema, data, root) } != 1
      yield error(schema, data, nil, 'not') if !not_schema.nil? && valid?(not_schema, data, root)

      if if_schema && valid?(if_schema, data, root)
        yield error(schema, data, nil, 'then') if !then_schema.nil? && !valid?(then_schema, data, root)
      elsif if_schema
        yield error(schema, data, nil, 'else') if !else_schema.nil? && !valid?(else_schema, data, root)
      end

      if ref
        _address, pointer = ref.split('#')
        ref_schema = Hana::Pointer.new(URI.unescape(pointer || '')).eval(root)
        if ref_schema == schema
          yield error(schema, data, nil, 'ref')
        elsif !ref_schema.nil?
          validate(ref_schema, data, root, &Proc.new)
        end
        return
      end

      case type
      when 'null'
        yield error(schema, data, nil, 'null') unless data.nil?
      when 'boolean'
        yield error(schema, data, nil, 'boolean') unless BOOLEANS.include?(data)
      when 'number'
        validate_number(schema, data, &Proc.new)
      when 'integer'
        validate_integer(schema, data, &Proc.new)
      when 'string'
        validate_string(schema, data, &Proc.new)
      when 'array'
        validate_array(schema, data, root, &Proc.new)
      when 'object'
        validate_object(schema, data, root, &Proc.new)
      when Array
        if type.all? { |subtype| !valid?(schema.merge('type' => subtype), data, root) }
          yield error(schema, data, nil, 'type')
        end
      else
        case data
        when Integer
          validate_integer(schema, data, &Proc.new)
        when Numeric
          validate_number(schema, data, &Proc.new)
        when String
          validate_string(schema, data, &Proc.new)
        when Array
          validate_array(schema, data, root, &Proc.new)
        when Hash
          validate_object(schema, data, root, &Proc.new)
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

    def validate_numeric(schema, data)
      multiple_of = schema['multipleOf']
      maximum = schema['maximum']
      exclusive_maximum = schema['exclusiveMaximum']
      minimum = schema['minimum']
      exclusive_minimum = schema['exclusiveMinimum']

      yield error(schema, data, nil, 'maximum') if maximum && data > maximum
      yield error(schema, data, nil, 'exclusiveMaximum') if exclusive_maximum && data >= exclusive_maximum
      yield error(schema, data, nil, 'minimum') if minimum && data < minimum
      yield error(schema, data, nil, 'exclusiveMinimum') if exclusive_minimum && data <= exclusive_minimum

      if multiple_of
        quotient = data / multiple_of.to_f
        yield error(schema, data, nil, 'multipleOf') unless quotient.floor == quotient
      end
    end

    def validate_number(schema, data)
      unless data.is_a?(Numeric)
        yield error(schema, data, nil, 'number')
        return
      end

      validate_numeric(schema, data, &Proc.new)
    end

    def validate_integer(schema, data)
      unless data.is_a?(Integer)
        yield error(schema, data, nil, 'integer')
        return
      end

      validate_numeric(schema, data, &Proc.new)
    end

    def validate_string(schema, data)
      unless data.is_a?(String)
        yield error(schema, data, nil, 'string')
        return
      end

      max_length = schema['maxLength']
      min_length = schema['minLength']
      pattern = schema['pattern']
      format = schema['format']

      yield error(schema, data, nil, 'maxLength') if max_length && data.size > max_length
      yield error(schema, data, nil, 'minLength') if min_length && data.size < min_length
      yield error(schema, data, nil, 'pattern') if pattern && !Regexp.new(pattern).match?(data)

      validate_string_format(format, data, &Proc.new) if format
    end

    def validate_string_format(format, string)
      valid = case format
      when 'date-time'
        valid_date_time?(string)
      when 'date'
        valid_date_time?("#{string}T04:05:06.123456789+07:00")
      when 'time'
        valid_date_time?("2001-02-03T#{string}")
      when 'email'
        valid_email?(string)
      when 'idn-email'
        valid_email?(string)
      when 'hostname', 'idn-hostname', 'ipv4', 'ipv6', 'uri', 'uri-reference', 'iri', 'iri-reference', 'uri-template', 'json-pointer', 'relative-json-pointer'
        true
      when 'regex'
        valid_regex?(string)
      end
      yield error(schema, data, nil, 'format') unless valid
    end

    def validate_array(schema, data, root, &block)
      unless data.is_a?(Array)
        yield error(schema, data, nil, 'array')
        return
      end

      items = schema['items']
      additional_items = schema['additionalItems']
      max_items = schema['maxItems']
      min_items = schema['minItems']
      unique_items = schema['uniqueItems']
      contains = schema['contains']

      yield error(schema, data, nil, 'maxItems') if max_items && data.size > max_items
      yield error(schema, data, nil, 'minItems') if min_items && data.size < min_items
      yield error(schema, data, nil, 'uniqueItems') if unique_items && data.size != data.uniq.size
      yield error(schema, data, nil, 'contains') if !contains.nil? && data.all? { |item| !valid?(contains, item, root) }

      if items.is_a?(Array)
        data.each_with_index do |item, index|
          if index < items.size
            validate(items[index], item, root, &block)
          elsif !additional_items.nil?
            validate(additional_items, item, root, &block)
          else
            break
          end
        end
      elsif !items.nil?
        data.each { |item| validate(items, item, root, &block) }
      end
    end

    def validate_object(schema, data, root, &block)
      unless data.is_a?(Hash)
        yield error(schema, data, nil, 'object')
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
          validate(subschema, data, root, &block)
        end
      end

      yield error(schema, data, nil, 'maxProperties') if max_properties && data.size > max_properties
      yield error(schema, data, nil, 'minProperties') if min_properties && data.size < min_properties
      yield error(schema, data, nil, 'required') if required && required.any? { |key| !data.key?(key) }

      regex_pattern_properties = nil
      data.each do |key, value|
        validate(property_names, key, root, &block) unless property_names.nil?

        matched_key = false

        if properties && properties.key?(key)
          validate(properties[key], value, root, &block)
          matched_key = true
        end

        if pattern_properties
          regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
            [Regexp.new(pattern), property_schema]
          end
          regex_pattern_properties.each do |regex, property_schema|
            if regex.match?(key)
              validate(property_schema, value, root, &block)
              matched_key = true
            end
          end
        end

        next if matched_key

        validate(additional_properties, value, root, &block) unless additional_properties.nil?
      end
    end

    def valid_date_time?(string)
      DateTime.rfc3339(string)
      true
    rescue ArgumentError => e
      raise e unless e.message == 'invalid date'
      false
    end

    def valid_email?(string)
      EMAIL_REGEX.match?(string)
    end

    def valid_regex?(string)
      Regexp.new(string)
      true
    rescue RegexpError
      false
    end
  end
end
