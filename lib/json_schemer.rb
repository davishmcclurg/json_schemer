# frozen_string_literal: true

require "json_schemer/version"

module JsonSchemer
  class << self
    def validate(schema, data)
      return enum_for(:validate, schema, data) unless block_given?

      return if schema == true
      if schema == false
        yield 'invalid'
        return
      end

      return if schema.empty?

      type = schema['type']
      enum = schema['enum']

      yield 'invalid enum' if enum && !enum.include?(data)
      yield 'invalid const' if schema.key?('const') && schema['const'] != data

      case type
      when 'null'
        yield 'invalid null' unless data.nil?
      when 'boolean'
        yield 'invalid boolean' unless data.is_a?(Boolean)
      when 'number'
        validate_number(schema, data, &Proc.new)
      when 'integer'
        validate_integer(schema, data, &Proc.new)
      when 'string'
        validate_string(schema, data, &Proc.new)
      when 'array'
        validate_array(schema, data, &Proc.new)
      when 'object'
        validate_object(schema, data, &Proc.new)
      else
        yield 'invalid schema type'
      end
    end

    def valid?(schema, data)
      !validate(schema, data).first
    end

  private

    def validate_numeric(schema, data)
      multiple_of = schema['multipleOf']
      maximum = schema['maximum']
      exclusive_maximum = schema['exclusiveMaximum']
      minimum = schema['minimum']
      exclusive_minimum = schema['exclusiveMinimum']

      yield 'invalid multiple of' if multiple_of && (data % multiple_of) != 0
      yield 'invalid maximum' if maximum && data > maximum
      yield 'invalid exclusive maximum' if exclusive_maximum && data >= exclusive_maximum
      yield 'invalid minimum' if minimum && data < minimum
      yield 'invalid exclusive minimum' if exclusive_minimum && data <= exclusive_minimum
    end

    def validate_number(schema, data)
      unless data.is_a?(Numeric)
        yield 'invalid number'
        return
      end

      validate_numeric(schema, data)
    end

    def validate_integer(schema, data)
      unless data.is_a?(Integer)
        yield 'invalid integer'
        return
      end

      validate_numeric(schema, data)
    end

    def validate_string(schema, data)
      unless data.is_a?(String)
        yield 'invalid string'
        return
      end

      max_length = schema['maxLength']
      min_length = schema['minLength']
      pattern = schema['pattern']

      yield 'invalid max length' if max_length && data.size > max_length
      yield 'invalid min length' if min_length && data.size < min_length
      yield 'invalid pattern' if pattern && !Regexp.new(pattern).match?(data)
    end

    def validate_array(schema, data, &block)
      unless data.is_a?(Array)
        yield 'invalid array'
        return
      end

      items = schema['items']
      additional_items = schema['additionalItems']
      max_items = schema['maxItems']
      min_items = schema['minItems']
      unique_items = schema['uniqueItems']
      contains = schema['contains']

      yield 'invalid max items' if max_items && data.size > max_items
      yield 'invalid min items' if min_items && data.size < min_items
      yield 'invalid unique items' if unique_items && data.size != data.uniq.size
      yield 'invalid contains' if contains && data.all? { |item| !valid?(contains, item) }

      if items.is_a?(Array)
        data.each_with_index do |item, index|
          if index < items.size
            validate(items[index], item, &block)
          elsif !additional_items.nil?
            validate(additional_items, item, &block)
          end
        end
      elsif !items.nil?
        data.each { |item| validate(items, item, &block) }
      end
    end

    def validate_object(schema, data, &block)
      unless data.is_a?(Hash)
        yield 'invalid object'
        return
      end

      max_properties = schema['maxProperties']
      min_properties = schema['minProperties']
      required = schema['required']
      properties = schema['properties']
      pattern_properties = schema['patternProperties']
      additional_properties = schema['additionalProperties']
      # dependencies = schema['dependencies']
      property_names = schema['propertyNames']

      yield 'invalid max properties' if max_properties && data.size > max_properties
      yield 'invalid min properties' if min_properties && data.size < min_properties
      yield 'invalid required' if required && required.any? { |key| !data.key?(key) }

      regex_pattern_properties = nil
      data.each_pair do |key, value|
        validate(property_names, key, &block) unless property_names.nil?

        if properties.key?(key)
          validate(properties[key], value, &block)
          next
        end

        if pattern_properties
          regex_pattern_properties ||= pattern_properties.map do |pattern, property_schema|
            [Regexp.new(pattern), property_schema]
          end
          matched = false
          regex_pattern_properties.each do |regex, property_schema|
            if regex.match?(key)
              validate(property_schema, value, &block)
              matched = true
            end
          end
          next if matched
        end

        validate(additional_properties, value, &block) unless additional_properties.nil?
      end
    end
  end
end
