# frozen_string_literal: true
require 'bundler/inline'

# Fixnum = Integer # jsonschema

gemfile do
  source 'https://rubygems.org'

  gem 'benchmark-ips'
  gem 'webrick'
  gem 'jschema'
  gem 'json-schema'
  gem 'json_schema'
  gem 'json_validation'
  # gem 'jsonschema'
  gem 'rj_schema'

  gem 'json_schemer', :path => '.'
end

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
    initialized_json_schemer = JSONSchemer.schema(schema)
    initialized_json_validation = JsonValidation.build_validator(schema)
    initialized_rj_schema = RjSchema::Validator.new('schema' => schema)

    # jschema

    # x.report("jschema, uninitialized, #{name}, valid") do
    #   errors = JSchema.build(schema).validate(valid)
    #   raise if errors.any?
    # end

    # x.report("jschema, uninitialized, #{name}, invalid") do
    #   errors = JSchema.build(schema).validate(invalid)
    #   raise if errors.empty?
    # end

    # x.report("jschema, initialized, #{name}, valid") do
    #   errors = initialized_jschema.validate(valid)
    #   raise if errors.any?
    # end

    # x.report("jschema, initialized, #{name}, invalid") do
    #   errors = initialized_jschema.validate(invalid)
    #   raise if errors.empty?
    # end

    # json-schema

    # x.report("json-schema, uninitialized, #{name}, valid") do
    #   errors = JSON::Validator.fully_validate(schema, valid)
    #   raise if errors.any?
    # end

    # x.report("json-schema, uninitialized, #{name}, invalid") do
    #   errors = JSON::Validator.fully_validate(schema, invalid)
    #   raise if errors.empty?
    # end

    # json_schema

    # x.report("json_schema, uninitialized, #{name}, valid") do
    #   success, errors = JsonSchema.parse!(schema).tap(&:expand_references!).validate(valid)
    #   raise if !success || errors.any?
    # end

    # x.report("json_schema, uninitialized, #{name}, invalid") do
    #   success, errors = JsonSchema.parse!(schema).tap(&:expand_references!).validate(invalid)
    #   raise if success || errors.empty?
    # end

    # x.report("json_schema, initialized, #{name}, valid") do
    #   success, errors = initialized_json_schema.validate(valid)
    #   raise if !success || errors.any?
    # end

    # x.report("json_schema, initialized, #{name}, invalid") do
    #   success, errors = initialized_json_schema.validate(invalid)
    #   raise if success || errors.empty?
    # end

    # json_schemer

    x.report("json_schemer, uninitialized, #{name}, valid, basic") do
      JSONSchemer.schema(schema).validate(valid, :output_format => 'basic').fetch('annotations')
    end

    x.report("json_schemer, uninitialized, #{name}, invalid, basic") do
      JSONSchemer.schema(schema).validate(invalid, :output_format => 'basic').fetch('errors')
    end

    x.report("json_schemer, initialized, #{name}, valid, basic") do
      initialized_json_schemer.validate(valid, :output_format => 'basic').fetch('annotations')
    end

    x.report("json_schemer, initialized, #{name}, invalid, basic") do
      initialized_json_schemer.validate(invalid, :output_format => 'basic').fetch('errors')
    end

    x.report("json_schemer, uninitialized, #{name}, valid, basic, to_a") do
      JSONSchemer.schema(schema).validate(valid, :output_format => 'basic').fetch('annotations').to_a
    end

    x.report("json_schemer, uninitialized, #{name}, invalid, basic, to_a") do
      JSONSchemer.schema(schema).validate(invalid, :output_format => 'basic').fetch('errors').to_a
    end

    x.report("json_schemer, initialized, #{name}, valid, basic, to_a") do
      initialized_json_schemer.validate(valid, :output_format => 'basic').fetch('annotations').to_a
    end

    x.report("json_schemer, initialized, #{name}, invalid, basic, to_a") do
      initialized_json_schemer.validate(invalid, :output_format => 'basic').fetch('errors').to_a
    end

    x.report("json_schemer, uninitialized, #{name}, valid, classic, to_a") do
      JSONSchemer.schema(schema).validate(valid).to_a
    end

    x.report("json_schemer, uninitialized, #{name}, invalid, classic, to_a") do
      JSONSchemer.schema(schema).validate(invalid).to_a
    end

    x.report("json_schemer, initialized, #{name}, valid, classic, to_a") do
      initialized_json_schemer.validate(valid).to_a
    end

    x.report("json_schemer, initialized, #{name}, invalid, classic, to_a") do
      initialized_json_schemer.validate(invalid).to_a
    end

    # json_validation

    # x.report("json_validation, uninitialized, #{name}, valid") do
    #   raise unless JsonValidation.build_validator(schema).validate(valid)
    # end

    # x.report("json_validation, uninitialized, #{name}, invalid") do
    #   raise if JsonValidation.build_validator(schema).validate(invalid)
    # end

    # x.report("json_validation, initialized, #{name}, valid") do
    #   raise unless initialized_json_validation.validate(valid)
    # end

    # x.report("json_validation, initialized, #{name}, invalid") do
    #   raise if initialized_json_validation.validate(invalid)
    # end

    # rj_schema

    # x.report("rj_schema, uninitialized, #{name}, valid") do
    #   errors = RjSchema::Validator.new.validate(schema, valid)
    #   raise if errors.fetch(:machine_errors).any?
    # end

    # x.report("rj_schema, uninitialized, #{name}, invalid") do
    #   errors = RjSchema::Validator.new.validate(schema, invalid)
    #   raise if errors.fetch(:machine_errors).empty?
    # end

    # x.report("rj_schema, initialized, #{name}, valid") do
    #   errors = initialized_rj_schema.validate(:"schema", valid)
    #   raise if errors.fetch(:machine_errors).any?
    # end

    # x.report("rj_schema, initialized, #{name}, invalid") do
    #   errors = initialized_rj_schema.validate(:"schema", invalid)
    #   raise if errors.fetch(:machine_errors).empty?
    # end

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
