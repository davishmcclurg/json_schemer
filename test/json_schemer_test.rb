require 'test_helper'
require 'csv'

class JSONSchemerTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil(JSONSchemer::VERSION)
  end

  def test_it_does_something_useful
    schema = {
      'type' => 'object',
      'maxProperties' => 4,
      'minProperties' => 1,
      'required' => [
        'one'
      ],
      'properties' => {
        'one' => {
          'type' => 'string',
          'maxLength' => 5,
          'minLength' => 3,
          'pattern' => '\w+'
        },
        'two' => {
          'type' => 'integer',
          'minimum' => 10,
          'maximum' => 100,
          'multipleOf' => 5
        },
        'three' => {
          'type' => 'array',
          'maxItems' => 2,
          'minItems' => 2,
          'uniqueItems' => true,
          'contains' => {
            'type' => 'integer'
          }
        }
      },
      'additionalProperties' => {
        'type' => 'string'
      },
      'propertyNames' => {
        'type' => 'string',
        'pattern' => '\w+'
      },
      'dependencies' => {
        'one' => [
          'two'
        ],
        'two' => {
          'minProperties' => 1
        }
      }
    }
    data = {
      'one' => 'value',
      'two' => 100,
      'three' => [1, 2],
      '123' => 'x'
    }
    schema = JSONSchemer.schema(schema)
    assert(schema.valid?(data))
    errors = schema.validate(data)
    assert(errors.none?)
  end

  def test_it_does_not_fail_when_the_schema_is_completely_empty
    schema = {}
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_required_validation_adds_missing_keys
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'schema1.json'))
    error = schema.validate({ 'id' => 1 }).first
    assert_equal('required', error.fetch('type'))
    assert_equal({ 'missing_keys' => ['a'] }, error.fetch('details'))
  end

  def test_it_handles_json_strings
    schema = JSONSchemer.schema('{ "type": "integer" }')
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_it_returns_nested_errors
    root = {
      'type' => 'object',
      'required' => [
        'numberOfModules'
      ],
      'properties' => {
        'numberOfModules' => {
          'allOf' => [
            {
              'not' => {
                'type' => 'integer',
                'minimum' => 38
              }
            },
            {
              'not' => {
                'type' => 'integer',
                'maximum' => 37,
                'minimum' => 25
              }
            },
            {
              'not' => {
                'type' => 'integer',
                'maximum' => 24,
                'minimum' => 12
              }
            }
          ],
          'anyOf' => [
            { 'type' => 'integer' },
            { 'type' => 'string' }
          ],
          'oneOf' => [
            { 'type' => 'integer' },
            { 'type' => 'integer' },
            { 'type' => 'boolean' }
          ]
        }
      }
    }
    schema = JSONSchemer.schema(root)
    assert_includes(
      schema.validate({ 'numberOfModules' => 32 }).to_a,
      {
        'data' => 32,
        'data_pointer' => '/numberOfModules',
        'schema' => {
          'not' => {
            'type' => 'integer',
            'maximum' => 37,
            'minimum' => 25
          }
        },
        'schema_pointer' => '/properties/numberOfModules/allOf/1',
        'root_schema' => root,
        'type' => 'not',
        'error' => 'value at `/numberOfModules` matches `not` schema'
      }
    )
    assert_equal(
      {
        'data' => true,
        'data_pointer' => '/numberOfModules',
        'schema' => {
          'type' => 'integer'
        },
        'schema_pointer' => '/properties/numberOfModules/anyOf/0',
        'root_schema' => root,
        'type' => 'integer',
        'error' => 'value at `/numberOfModules` is not an integer'
      },
      schema.validate({ 'numberOfModules' => true }).first
    )
    assert_equal(
      {
        'data' => 8,
        'data_pointer' => '/numberOfModules',
        'schema' => root.fetch('properties').fetch('numberOfModules'),
        'schema_pointer' => '/properties/numberOfModules',
        'root_schema' => root,
        'type' => 'oneOf',
        'error' => 'value at `/numberOfModules` does not match exactly one `oneOf` schema'
      },
      schema.validate({ 'numberOfModules' => 8 }).first
    )
  end

  def test_it_validates_correctly_custom_keywords
    options = {
      keywords: {
        'ignored' => nil,
        'even' => lambda do |data, curr_schema, _pointer|
          curr_schema.fetch('even') == data.to_i.even?
        end
      }
    }

    schema = JSONSchemer.schema({ 'even' => true }, **options)
    assert(schema.valid?(2))
    refute(schema.valid?(3))

    options = {
      keywords: {
        'two' => lambda do |data, curr_schema, _pointer|
          if curr_schema.fetch('two') == (data == 2)
            []
          else
            ['error1', 'error2']
          end
        end
      }
    }

    schema = JSONSchemer.schema({ 'two' => true }, **options)
    assert_equal([], schema.validate(2).to_a)
    errors = schema.validate(3).map { |error| error.fetch('type') }
    assert_equal(['error1', 'error2'], errors)
    refute(schema.valid?(3))
  end

  def test_it_validates_custom_keywords_in_nested_schemas
    schemer = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'yah' => true
          }
        }
      },
      keywords: {
        'yah' => proc do |instance, _schema, _instance_location|
          instance == 'valid'
        end
      }
    )
    assert(schemer.valid?({ 'x' => 'valid' }))
    refute(schemer.valid?({ 'x' => 'invalid' }))
  end

  def test_custom_keywords_receive_resolved_instance_location
    custom_keyword_instance_location = nil
    schemer = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'yah' => true
          },
          'y' => {
            'yah' => true
          }
        }
      },
      keywords: {
        'yah' => proc do |instance, _schema, instance_location|
          custom_keyword_instance_location = instance_location
          instance == 'valid'
        end
      }
    )
    assert(schemer.valid?({ 'x' => 'valid' }))
    assert_equal('/x', custom_keyword_instance_location)
    refute(schemer.valid?({ 'y' => 'invalid' }))
    assert_equal('/y', custom_keyword_instance_location)
  end

  def test_it_handles_multiple_of_floats
    assert(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.61))
    refute(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.666))
    assert(JSONSchemer.schema({ 'multipleOf' => 0.001 }).valid?(8.666))
  end

  def test_it_escapes_json_pointer_tokens
    schemer = JSONSchemer.schema(
      {
        'type' => 'object',
        'properties' => {
          'foo/bar~' => {
            'type' => 'string'
          }
        }
    }
    )
    errors = schemer.validate({ 'foo/bar~' => 1 }).to_a
    assert_equal(1, errors.size)
    assert_equal('/foo~1bar~0', errors.first.fetch('data_pointer'))
    assert_equal('/properties/foo~1bar~0', errors.first.fetch('schema_pointer'))
  end

  def test_it_ignores_invalid_types
    assert(JSONSchemer.schema({ 'type' => 'invalid' }).valid?({}))
    assert(JSONSchemer.schema({ 'type' => Object.new }).valid?({}))
  end

  def test_it_raises_for_unsupported_content_encoding
    assert_raises(JSONSchemer::UnknownContentEncoding) { JSONSchemer.schema({ 'contentEncoding' => '7bit' }) }
  end

  def test_it_raises_for_unsupported_content_media_type
    assert_raises(JSONSchemer::UnknownContentMediaType) { JSONSchemer.schema({ 'contentMediaType' => 'application/xml' }) }
  end

  def test_it_raises_for_required_unknown_vocabulary
    assert_raises(JSONSchemer::UnknownVocabulary) { JSONSchemer.schema({}, :vocabulary => { 'unknown' => true }) }
  end

  def test_it_raises_for_unknown_output_format
    assert_raises(JSONSchemer::UnknownOutputFormat) { JSONSchemer.schema({}, :output_format => 'unknown').validate(1) }
    assert_raises(JSONSchemer::UnknownOutputFormat) { JSONSchemer.schema({}).validate(1, :output_format => 'unknown') }
  end

  def test_it_raises_for_unsupported_meta_schema
    assert_raises(JSONSchemer::UnsupportedMetaSchema) { JSONSchemer.schema({}, :meta_schema => 'unsupported') }
  end

  def test_string_meta_schema
    assert_equal(JSONSchemer.draft6, JSONSchemer.schema({}, :meta_schema => JSONSchemer::Draft6::BASE_URI.to_s).meta_schema)
  end

  def test_default_meta_schema
    assert_equal(JSONSchemer.draft202012, JSONSchemer::Schema.new({}).meta_schema)
  end

  def test_draft4_default_id
    assert_equal(JSONSchemer::Schema::DEFAULT_BASE_URI, JSONSchemer.schema(true, :meta_schema => JSONSchemer::Draft4::BASE_URI.to_s).base_uri)
  end

  def test_it_ignores_content_schema_without_content_media_type
    assert(JSONSchemer.schema({ 'contentSchema' => false }).valid?(1))
  end

  def test_draft7_additional_items_error
    schemer = JSONSchemer.schema({ 'items' => [true], 'additionalItems' => false }, :meta_schema => JSONSchemer.draft7, :output_format => 'verbose')
    assert_equal('array items at root do not match `additionalItems` schema', schemer.validate([1, 2], :resolve_enumerators => true).dig('errors', 1, 'error'))
  end

  def test_unevaluated_items_errors
    schemer = JSONSchemer.schema({
      'prefixItems' => [
        { 'type' => 'integer' }
      ],
      'unevaluatedItems' => false
    })
    assert_equal(['/prefixItems/0'], schemer.validate(['invalid']).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/unevaluatedItems'], schemer.validate([1, 'unevaluated']).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/prefixItems/0', '/unevaluatedItems'], schemer.validate(['invalid', 'unevaluated']).map { |error| error.fetch('schema_pointer') })
  end

  def test_unevaluated_properties_errors
    schemer = JSONSchemer.schema({
      'properties' => {
        'foo' => {
          'type' => 'integer'
        }
      },
      'unevaluatedProperties' => false
    })
    assert_equal(['/properties/foo'], schemer.validate({ 'foo' => 'invalid' }).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/unevaluatedProperties'], schemer.validate({ 'bar' => 'unevaluated' }).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/unevaluatedProperties'], schemer.validate({ 'foo' => 1, 'bar' => 'unevaluated' }).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/properties/foo', '/unevaluatedProperties'], schemer.validate({ 'foo' => 'invalid', 'bar' => '?' }).map { |error| error.fetch('schema_pointer') })

    schemer = JSONSchemer.schema({
      'properties' => {
        'foo' => {
          'type' => 'integer'
        },
        'bar' => {
          'type' => 'string'
        }
      },
      'unevaluatedProperties' => false
    })
    assert_equal(['/properties/foo'], schemer.validate({ 'foo' => 'invalid', 'bar' => 'valid' }).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/properties/bar'], schemer.validate({ 'foo' => 1, 'bar' => 1 }).map { |error| error.fetch('schema_pointer') })
  end

  # https://github.com/json-schema-org/json-schema-spec/issues/1172#issuecomment-1062540587
  def test_unevaluated_properties_inconsistent_errors
    all_of = [
      {
        'properties' => {
          'foo' => true
        }
      },
      false
    ]
    schemer1 = JSONSchemer.schema({
      'allOf' => all_of,
      'unevaluatedProperties' => false
    })
    schemer2 = JSONSchemer.schema({
      'allOf' => [
        { 'allOf' => all_of }
      ],
      'unevaluatedProperties' => false
    })
    instance = {
      'foo' => true
    }
    assert_equal(['/allOf/1'], schemer1.validate(instance).map { |error| error.fetch('schema_pointer') })
    assert_equal(['/allOf/0/allOf/1', '/unevaluatedProperties'], schemer2.validate(instance).map { |error| error.fetch('schema_pointer') })
  end

  def test_inspect
    output = JSONSchemer.openapi31_document.inspect
    assert_includes(output, 'JSONSchemer::Schema')
    assert_includes(output, '@value=')
  end

  def test_it_allows_validating_schemas
    valid_draft7_schema = { '$ref' => '#/definitions/~1some~1%7Bid%7D' }
    invalid_draft7_schema = { '$ref' => '#/definitions/~1some~1{id}' }
    valid_draft4_schema = invalid_draft7_schema
    invalid_draft4_schema = { 'properties' => { 'x' => { 'exclusiveMaximum' => true } } }
    valid_detected_draft4_schema = valid_draft4_schema.merge('$schema' => 'http://json-schema.org/draft-04/schema#')
    invalid_detected_draft4_schema = invalid_draft4_schema.merge('$schema' => 'http://json-schema.org/draft-04/schema#')
    format_error = {
      'data' => '#/definitions/~1some~1{id}',
      'data_pointer' => '/$ref',
      'schema' => { 'type' => 'string', 'format' => 'uri-reference' },
      'schema_pointer' => '/properties/$ref',
      'root_schema' => JSONSchemer::Draft7::SCHEMA,
      'type' => 'format',
      'error' => 'value at `/$ref` does not match format: uri-reference'
    }
    required_error = {
      'data' => { 'exclusiveMaximum' => true },
      'data_pointer' => '/properties/x',
      'schema' => JSONSchemer::Draft4::SCHEMA,
      'schema_pointer' => '',
      'root_schema' => JSONSchemer::Draft4::SCHEMA,
      'type' => 'dependencies',
      'details' => { 'missing_keys' => ['maximum'] },
      'error' => 'object at `/properties/x` either does not match applicable `dependencies` schemas or is missing required `dependencies` properties'
    }

    draft7_meta_schema = JSONSchemer.draft7
    draft4_meta_schema = JSONSchemer.draft4

    assert(JSONSchemer.valid_schema?(valid_draft7_schema, :meta_schema => draft7_meta_schema))
    refute(JSONSchemer.valid_schema?(invalid_draft7_schema, :meta_schema => draft7_meta_schema))
    assert(JSONSchemer.schema(valid_draft7_schema, :meta_schema => draft7_meta_schema).valid_schema?)
    refute(JSONSchemer.schema(invalid_draft7_schema, :meta_schema => draft7_meta_schema).valid_schema?)

    assert_empty(JSONSchemer.validate_schema(valid_draft7_schema, :meta_schema => draft7_meta_schema).to_a)
    assert_equal([format_error], JSONSchemer.validate_schema(invalid_draft7_schema, :meta_schema => draft7_meta_schema).to_a)
    assert_empty(JSONSchemer.schema(valid_draft7_schema, :meta_schema => draft7_meta_schema).validate_schema.to_a)
    assert_equal([format_error], JSONSchemer.schema(invalid_draft7_schema, :meta_schema => draft7_meta_schema).validate_schema.to_a)

    assert(JSONSchemer.valid_schema?(valid_draft4_schema, :meta_schema => draft4_meta_schema))
    refute(JSONSchemer.valid_schema?(invalid_draft4_schema, :meta_schema => draft4_meta_schema))
    assert(JSONSchemer::valid_schema?(valid_detected_draft4_schema))
    refute(JSONSchemer::valid_schema?(invalid_detected_draft4_schema))

    assert_empty(JSONSchemer.validate_schema(valid_draft7_schema, :meta_schema => draft4_meta_schema).to_a)
    assert_equal([required_error], JSONSchemer.validate_schema(invalid_draft4_schema, :meta_schema => draft4_meta_schema).to_a)
    assert_empty(JSONSchemer.validate_schema(valid_detected_draft4_schema).to_a)
    assert_equal([required_error], JSONSchemer.validate_schema(invalid_detected_draft4_schema).to_a)
  end

  def test_schema_validation_invalid_meta_schema
    refute(JSONSchemer.valid_schema?({ '$schema' => {} }))
  end

  def test_schema_validation_parse_error
    refute(JSONSchemer.valid_schema?({ 'properties' => '' }))
    assert(JSONSchemer.valid_schema?({ 'properties' => {} }))
    assert(JSONSchemer.valid_schema?({ 'items' => {} }))
    refute(JSONSchemer.valid_schema?({ 'items' => [{}] }))
    assert(JSONSchemer.valid_schema?({ 'items' => [{}] }, :meta_schema => JSONSchemer.draft201909))
    assert(JSONSchemer.valid_schema?({ '$schema' => 'https://json-schema.org/draft/2019-09/schema', 'items' => [{}] }))
    assert(JSONSchemer.valid_schema?({ '$schema': 'https://json-schema.org/draft/2019-09/schema', 'items' => [{}] }))

    refute_empty(JSONSchemer.validate_schema({ 'properties' => '' }).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'properties' => {} }).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => {} }).to_a)
    refute_empty(JSONSchemer.validate_schema({ 'items' => [{}] }).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => [{}] }, :meta_schema => JSONSchemer.draft201909).to_a)
    assert_empty(JSONSchemer.validate_schema({ '$schema' => 'https://json-schema.org/draft/2019-09/schema', 'items' => [{}] }).to_a)
    assert_empty(JSONSchemer.validate_schema({ '$schema': 'https://json-schema.org/draft/2019-09/schema', 'items' => [{}] }).to_a)
  end

  def test_schema_validation_parse_error_with_custom_meta_schema
    custom_meta_schema = {
      '$vocabulary' => {},
      'oneOf' => [
        { 'required' => ['$id'] },
        { 'required' => ['items'] }
      ],
      'properties' => {
        'items' => {
          'type' => 'string'
        }
      }
    }
    custom_meta_schemer = JSONSchemer.schema(custom_meta_schema)
    ref_resolver = {
      URI('https://example.com/custom-meta-schema') => custom_meta_schema
    }.to_proc

    assert(JSONSchemer.valid_schema?({}))
    refute(JSONSchemer.valid_schema?({}, meta_schema: custom_meta_schemer))
    refute(JSONSchemer.valid_schema?({ '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    refute(JSONSchemer.valid_schema?({ '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    refute(JSONSchemer.valid_schema?({ '$id' => {} }))
    assert(JSONSchemer.valid_schema?({ '$id' => {} }, meta_schema: custom_meta_schemer))
    assert(JSONSchemer.valid_schema?({ '$id' => {}, '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    assert(JSONSchemer.valid_schema?({ '$id' => {}, '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    assert(JSONSchemer.valid_schema?({ 'items' => {} }))
    refute(JSONSchemer.valid_schema?({ 'items' => 'yah' }))
    refute(JSONSchemer.valid_schema?({ 'items' => {} }, meta_schema: custom_meta_schemer))
    assert(JSONSchemer.valid_schema?({ 'items' => 'yah' }, meta_schema: custom_meta_schemer))
    refute(JSONSchemer.valid_schema?({ 'items' => {}, '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    assert(JSONSchemer.valid_schema?({ 'items' => 'yah', '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    refute(JSONSchemer.valid_schema?({ 'items' => {}, '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))
    assert(JSONSchemer.valid_schema?({ 'items' => 'yah', '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver))

    assert_empty(JSONSchemer.validate_schema({}).to_a)
    refute_empty(JSONSchemer.validate_schema({}, meta_schema: custom_meta_schemer).to_a)
    refute_empty(JSONSchemer.validate_schema({ '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    refute_empty(JSONSchemer.validate_schema({ '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    refute_empty(JSONSchemer.validate_schema({ '$id' => {} }).to_a)
    assert_empty(JSONSchemer.validate_schema({ '$id' => {} }, meta_schema: custom_meta_schemer).to_a)
    assert_empty(JSONSchemer.validate_schema({ '$id' => {}, '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    assert_empty(JSONSchemer.validate_schema({ '$id' => {}, '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => {} }).to_a)
    refute_empty(JSONSchemer.validate_schema({ 'items' => 'yah' }).to_a)
    refute_empty(JSONSchemer.validate_schema({ 'items' => {} }, meta_schema: custom_meta_schemer).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => 'yah' }, meta_schema: custom_meta_schemer).to_a)
    refute_empty(JSONSchemer.validate_schema({ 'items' => {}, '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => 'yah', '$schema' => 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    refute_empty(JSONSchemer.validate_schema({ 'items' => {}, '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
    assert_empty(JSONSchemer.validate_schema({ 'items' => 'yah', '$schema': 'https://example.com/custom-meta-schema' }, ref_resolver: ref_resolver).to_a)
  end

  def test_schema_validation_json
    refute(JSONSchemer.valid_schema?('{"$schema":{}}'))
    assert(JSONSchemer.valid_schema?('{"items":{}}'))
    refute(JSONSchemer.valid_schema?('{"items":[{}]}'))
    assert(JSONSchemer.valid_schema?('{"items":[{}]}', :meta_schema => JSONSchemer.draft201909))
    assert(JSONSchemer.valid_schema?('{"items":[{}],"$schema":"https://json-schema.org/draft/2019-09/schema"}'))

    refute_empty(JSONSchemer.validate_schema('{"$schema":{}}').to_a)
    assert_empty(JSONSchemer.validate_schema('{"items":{}}').to_a)
    refute_empty(JSONSchemer.validate_schema('{"items":[{}]}').to_a)
    assert_empty(JSONSchemer.validate_schema('{"items":[{}]}', :meta_schema => JSONSchemer.draft201909).to_a)
    assert_empty(JSONSchemer.validate_schema('{"items":[{}],"$schema":"https://json-schema.org/draft/2019-09/schema"}').to_a)
  end

  def test_schema_validation_pathname
    schema_invalid = Pathname.new(__dir__).join('schemas', '$schema_invalid.json')
    items_object = Pathname.new(__dir__).join('schemas', 'items_object.json')
    items_array = Pathname.new(__dir__).join('schemas', 'items_array.json')
    schema_items_array = Pathname.new(__dir__).join('schemas', '$schema_items_array.json')

    refute(JSONSchemer.valid_schema?(schema_invalid))
    assert(JSONSchemer.valid_schema?(items_object))
    refute(JSONSchemer.valid_schema?(items_array))
    assert(JSONSchemer.valid_schema?(items_array, :meta_schema => JSONSchemer.draft201909))
    assert(JSONSchemer.valid_schema?(schema_items_array))

    refute_empty(JSONSchemer.validate_schema(schema_invalid).to_a)
    assert_empty(JSONSchemer.validate_schema(items_object).to_a)
    refute_empty(JSONSchemer.validate_schema(items_array).to_a)
    assert_empty(JSONSchemer.validate_schema(items_array, :meta_schema => JSONSchemer.draft201909).to_a)
    assert_empty(JSONSchemer.validate_schema(schema_items_array).to_a)
  end

  def test_non_string_keys
    schemer = JSONSchemer.schema({
      properties: {
        'title' => {
          type: 'string'
        },
        :description => {
          'type' => 'string'
        }
      }
    })
    assert(schemer.valid?({ title: 'some title' }))
    assert(schemer.valid?({ 'title' => 'some title' }))
    refute(schemer.valid?({ title: :sometitle }))
    refute(schemer.valid?({ 'title' => :sometitle }))
    assert(schemer.valid?({ description: 'some description' }))
    assert(schemer.valid?({ 'description' => 'some description' }))
    refute(schemer.valid?({ description: :somedescription }))
    refute(schemer.valid?({ 'description' => :somedescription }))

    schemer = JSONSchemer.schema({
      'properties' => {
        '1' => {
          'const' => 'one'
        },
        2 => {
          :const => 'two'
        }
      }
    })
    assert(schemer.valid?({ 1 => 'one' }))
    assert(schemer.valid?({ '1' => 'one' }))
    refute(schemer.valid?({ 1 => 'neo' }))
    refute(schemer.valid?({ '1' => 'neo' }))
    assert(schemer.valid?({ 2 => 'two' }))
    assert(schemer.valid?({ '2' => 'two' }))
    refute(schemer.valid?({ 2 => 'tow' }))
    refute(schemer.valid?({ '2' => 'tow' }))
  end

  def test_schema_ref
    schemer = JSONSchemer.schema({
      'type' => 'integer',
      '$defs' => {
        'foo' => {
          '$id' => 'subschemer',
          '$defs' => {
            'bar' => {
              'required' => ['z']
            }
          },
          'type' => 'object',
          'required' => ['x', 'y'],
          'properties' => {
            'x' => {
              'type' => 'string'
            },
            'y' => {
              'type' => 'integer'
            }
          }
        }
      }
    })

    assert(schemer.valid?(1))
    refute(schemer.valid?('1'))

    subschemer = schemer.ref('#/$defs/foo')

    refute(subschemer.valid?(1))
    assert_equal(
      [['/x', '/$defs/foo/properties/x', 'string'], ['', '/$defs/foo', 'required']],
      subschemer.validate({ 'x' => 1 }).map { |error| error.values_at('data_pointer', 'schema_pointer', 'type') }
    )
    assert(subschemer.valid?({ 'x' => '1', 'y' => 1 }))

    subsubschemer = subschemer.ref('#/$defs/bar')
    refute(subsubschemer.valid?({ 'x' => 1 }))
    assert_equal(
      [['', '/$defs/foo/$defs/bar', 'required']],
      subsubschemer.validate({ 'x' => 1 }).map { |error| error.values_at('data_pointer', 'schema_pointer', 'type') }
    )

    assert_equal(subschemer, subschemer.ref('#'))
    assert_equal(subschemer, subsubschemer.ref('#'))
  end

  def test_published_meta_schemas
    [
      JSONSchemer::Draft202012::SCHEMA,
      *JSONSchemer::Draft202012::Meta::SCHEMAS.values,
      JSONSchemer::Draft201909::SCHEMA,
      *JSONSchemer::Draft201909::Meta::SCHEMAS.values,
      JSONSchemer::Draft7::SCHEMA,
      JSONSchemer::Draft6::SCHEMA,
      JSONSchemer::Draft4::SCHEMA,
      JSONSchemer::OpenAPI31::SCHEMA,
      JSONSchemer::OpenAPI31::Meta::BASE,
      # fixme: https://github.com/OAI/OpenAPI-Specification/pull/3455
      # JSONSchemer::OpenAPI31::Document::SCHEMA,
      # JSONSchemer::OpenAPI30::Document::SCHEMA
    ].each do |meta_schema|
      id = meta_schema.key?('$id') ? meta_schema.fetch('$id') : meta_schema.fetch('id')
      assert_equal(meta_schema, JSON.parse(fetch(id)))
    end
  end

  def test_bundle
    schema = {
      'allOf' => [
        { '$ref' => 'one' },
        { '$ref' => 'two' },
        { '$ref' => '#four' },
        { '$ref' => '#/$defs/four' },
        { '$ref' => 'five#/$defs/digit' },
        { '$ref' => 'six#plus' },
        { '$ref' => 'seven' }
      ],
      '$defs' => {
        'four' => {
          '$anchor' => 'four',
          'maxLength' => 1
        }
      }
    }
    refs = {
      URI('json-schemer://schema/one') => {
        'type' => 'string'
      },
      URI('json-schemer://schema/two') => {
        '$ref' => 'three'
      },
      URI('json-schemer://schema/three') => {
        'minLength' => 1
      },
      URI('json-schemer://schema/five') => {
        '$defs' => {
          'digit' => {
            'pattern' => '^\d*$'
          }
        }
      },
      URI('json-schemer://schema/six') => {
        '$defs' => {
          '?' => {
            '$anchor' => 'plus',
            'pattern' => '^[6-9]*$'
          }
        }
      },
      URI('json-schemer://schema/seven') => {
        '$id' => 'different',
        'enum' => ['6', '7']
      }
    }
    schemer = JSONSchemer.schema(schema, :ref_resolver => refs.to_proc)
    assert(schemer.valid?('6'))
    refute(schemer.valid?(''))
    refute(schemer.valid?('22'))
    refute(schemer.valid?('x'))
    refute(schemer.valid?('5'))
    refute(schemer.valid?('8'))
    assert(schemer.valid?('7'))

    compound_document = schemer.bundle

    assert_equal(
      [
        'four',
        'json-schemer://schema/one',
        'json-schemer://schema/two',
        'json-schemer://schema/three',
        'json-schemer://schema/five',
        'json-schemer://schema/six',
        'json-schemer://schema/seven'
      ].sort,
      compound_document.fetch('$defs').keys.sort
    )

    bundle = JSONSchemer.schema(compound_document)
    assert(bundle.valid?('6'))
    refute(bundle.valid?(''))
    refute(bundle.valid?('22'))
    refute(bundle.valid?('x'))
    refute(bundle.valid?('5'))
    refute(bundle.valid?('8'))
    assert(bundle.valid?('7'))
  end

  def test_bundle_exclusive_ref
    schema = {
      '$schema' => 'http://json-schema.org/draft-07/schema#',
      '$ref' => 'external',
      'allOf' => [true]
    }
    refs = {
      URI('json-schemer://schema/external') => {
        'const' => 'yah'
      }
    }
    schemer = JSONSchemer.schema(schema, :ref_resolver => refs.to_proc)
    assert(schemer.valid?('yah'))
    refute(schemer.valid?('nah'))

    compound_document = schemer.bundle

    assert_equal([true, { '$ref' => 'external' }], compound_document.fetch('allOf'))

    bundle = JSONSchemer.schema(schemer.bundle)
    assert(bundle.valid?('yah'))
    refute(bundle.valid?('nah'))
  end

  def test_custom_content_encodings_and_media_types
    data = '😊'
    instance = Base64.urlsafe_encode64(data)
    schema = {
      'contentEncoding' => 'urlsafe_base64',
      'contentMediaType' => 'text/csv'
    }
    content_encodings = {
      'urlsafe_base64' => proc do |instance|
        [true, Base64.urlsafe_decode64(instance).force_encoding('utf-8')]
      rescue
        [false, nil]
      end
    }
    content_media_types = {
      'text/csv' => proc do |instance|
        [true, CSV.parse(instance)]
      rescue
        [false, nil]
      end
    }

    refute(JSONSchemer.schema({ 'contentEncoding' => 'base64' }).validate(instance, :output_format => 'basic').fetch('annotations').first.key?('annotation'))

    schemer = JSONSchemer.schema(schema, :content_encodings => content_encodings, :content_media_types => content_media_types)

    assert_nil(annotation(schemer.validate('invalid', :output_format => 'basic'), '/contentEncoding'))
    assert_nil(annotation(schemer.validate(Base64.urlsafe_encode64("#{data}\""), :output_format => 'basic'), '/contentMediaType'))

    result = schemer.validate(instance, :output_format => 'basic')
    assert_equal(data, annotation(result, '/contentEncoding'))
    assert_equal([[data]], annotation(result, '/contentMediaType'))

    draft7_schemer = JSONSchemer.schema(
      schema,
      :meta_schema => JSONSchemer.draft7,
      :content_encodings => content_encodings,
      :content_media_types => content_media_types
    )

    assert(draft7_schemer.valid?(instance))
    refute(draft7_schemer.valid?('invalid'))
    refute(draft7_schemer.valid?(Base64.urlsafe_encode64("#{data}\"")))
  end

private

  def annotation(result, keyword_location)
    result.fetch('annotations').find { |annotation| annotation.fetch('keywordLocation') == keyword_location }['annotation']
  end
end
