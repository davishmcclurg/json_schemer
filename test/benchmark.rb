# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require "benchmark/ips"
require "jschema"
require "json-schema"
require "json_schema"
require "json_schemer"
require "json_validation"
# require "jsonschema"

# json_validation
require "digest"

benchmarks = {
  'simple' => {
    'schema' => {
      'type' => 'object',
      'properties' => {
        'firstName' => {
          'type' => 'string'
        },
        'lastName' => {
          'type' => 'string'
        },
        'age' => {
          'type' => 'integer',
          'minimum' => 0
        }
      },
      'required' => [
        'firstName',
        'lastName'
      ]
    },
    'valid' => {
      'firstName' => 'Jean-Luc',
      'lastName' => 'Picard',
      'age' => 51
    },
    'invalid' => {
      'lastName' => 'Janeway',
      'age' => 41.1
    }
  }
}

Benchmark.ips do |x|
  benchmarks.each do |name, defn|
    schema, valid, invalid = defn.values_at('schema', 'valid', 'invalid')

    initialized_jschema = JSchema.build(schema)
    initialized_json_schema = JsonSchema.parse!(schema).tap(&:expand_references!)
    initialized_json_schemer = JSONSchemer::Schema.new(schema)
    initialized_json_validation = JsonValidation.build_validator(schema)

    # jschema

    x.report("jschema, uninitialized, #{name}, valid") do
      errors = JSchema.build(schema).validate(valid)
      raise if errors.any?
    end

    x.report("jschema, uninitialized, #{name}, invalid") do
      errors = JSchema.build(schema).validate(invalid)
      raise if errors.empty?
    end

    x.report("jschema, initialized, #{name}, valid") do
      errors = initialized_jschema.validate(valid)
      raise if errors.any?
    end

    x.report("jschema, initialized, #{name}, invalid") do
      errors = initialized_jschema.validate(invalid)
      raise if errors.empty?
    end

    # json-schema

    x.report("json-schema, #{name}, valid") do
      raise unless JSON::Validator.validate(schema, valid)
    end

    x.report("json-schema, #{name}, invalid") do
      raise if JSON::Validator.validate(schema, invalid)
    end

    # json_schema

    x.report("json_schema, uninitialized, #{name}, valid") do
      success, errors = JsonSchema.parse!(schema).tap(&:expand_references!).validate(valid)
      raise if !success || errors.any?
    end

    x.report("json_schem, uninitialized, #{name}, invalid") do
      success, errors = JsonSchema.parse!(schema).tap(&:expand_references!).validate(invalid)
      raise if success || errors.empty?
    end

    x.report("json_schema, initialized, #{name}, valid") do
      success, errors = initialized_json_schema.validate(valid)
      raise if !success || errors.any?
    end

    x.report("json_schem, initialized, #{name}, invalid") do
      success, errors = initialized_json_schema.validate(invalid)
      raise if success || errors.empty?
    end

    # json_schemer

    x.report("json_schemer, uninitialized, #{name}, valid") do
      errors = JSONSchemer::Schema.new(schema).validate(valid).to_a
      raise if errors.any?
    end

    x.report("json_schemer, uninitialized, #{name}, invalid") do
      errors = JSONSchemer::Schema.new(schema).validate(invalid).to_a
      raise if errors.empty?
    end

    x.report("json_schemer, initialized, #{name}, valid") do
      errors = initialized_json_schemer.validate(valid).to_a
      raise if errors.any?
    end

    x.report("json_schemer, initialized, #{name}, invalid") do
      errors = initialized_json_schemer.validate(invalid).to_a
      raise if errors.empty?
    end

    # json_validation

    x.report("json_validation, uninitialized, #{name}, valid") do
      raise unless JsonValidation.build_validator(schema).validate(valid)
    end

    x.report("json_validation, uninitialized, #{name}, invalid") do
      raise if JsonValidation.build_validator(schema).validate(invalid)
    end

    x.report("json_validation, initialized, #{name}, valid") do
      raise unless initialized_json_validation.validate(valid)
    end

    x.report("json_validation, initialized, #{name}, invalid") do
      raise if initialized_json_validation.validate(invalid)
    end

    # jsonschema

    # x.report("jsonschema, #{name}, valid") do
    #   JSON::Schema.validate(valid, schema)
    # end

    # x.report("jsonschema, #{name}, invalid") do
    #   JSON::Schema.validate(invalid, schema)
    # rescue JSON::Schema::ValueError
    # else
    #   raise
    # end
  end

  x.compare!
end
