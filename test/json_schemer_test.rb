require 'test_helper'

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

  def test_it_inserts_defaults
    schema = {
      'required' => ['a', 'c', 'd'],
      'properties' => {
        'a' => { 'default' => 1 },
        'b' => { 'default' => 2 },
        'c' => {
          'required' => ['x'],
          'properties' => {
            'x' => { 'default' => 3 },
            'y' => { 'default' => 4 }
          }
        },
        'd' => {
          'required' => ['x'],
          'default' => {
            'x' => {
              'y' => {
                'z' => 1
              }
            }
          },
          'properties' => {
            'x' => {
              'required' => ['y'],
              'properties' => {
                'y' => {
                  'required' => ['z'],
                  'properties' => {
                    'z' => { 'type' => 'integer' }
                  }
                }
              }
            }
          }
        }
      }
    }
    data = {
      'a' => 10,
      'c' => {
        'x' => 30
      }
    }
    refute(JSONSchemer.schema(schema).valid?(data))
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal(
      {
        'a' => 10,
        'b' => 2,
        'c' => {
          'x' => 30,
          'y' => 4
        },
        'd' => {
          'x' => {
            'y' => {
              'z' => 1
            }
          }
        }
      },
      data
    )
  end

  def test_it_does_not_fail_using_insert_defaults_when_no_properties_are_defined_by_schema
    schema = {
      '$comment' => 'Mostly empty schema'
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property
    schema = {
      'properties' => {
        'a' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_fail_using_insert_defaults_when_properties_contains_a_boolean_defined_property_that_does_not_exist
    schema = {
      'properties' => {
        'b' => true
      }
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_does_not_insert_defaults_in_conditional_subschemas
    subschema = {
      'properties' => {
        'a' => {
          'const' => 1
        },
        'b' => {
          'const' => 2,
          'default' => 2
        }
      }
    }
    schema = {
      'allOf' => [subschema],
      'anyOf' => [subschema],
      'oneOf' => [subschema],
      'if' => subschema
    }
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema, insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
    refute(JSONSchemer.schema(schema.merge('not' => subschema), insert_property_defaults: true).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_calls_before_validation_hooks_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        parsed = data[property].split(',')
        parsed = parsed.map!(&:to_i) if property_schema['items']['type'] == 'integer'
        data[property] = parsed
      end
    end
    data = { 'list' => '1,2,3' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [parse_array]
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3]}, data)
  end

  def test_use_before_validation_hook_to_act_on_parent_schema
    skip_read_only = proc do |data, property, property_schema, schema|
      return unless property_schema['readOnly']
      schema['required'].delete(property) if schema['required']
      if data.key?(property) && property_schema.is_a?(Hash)
        data.delete(property)
      end
    end
    schema = {
      'required' => ['id'],
      'properties' => {
        'id' => {
          'type' => 'integer',
          'readOnly' => true
        }
      }
    }
    schemer = JSONSchemer.schema(
      schema,
      before_property_validation: [skip_read_only]
    )
    data = { 'id' => 1 }
    assert_empty(schemer.validate(data).to_a)
    assert_equal({}, data)

    data = {}
    assert_empty(schemer.validate(data).to_a)
    assert_equal({}, data)
  end

  def test_it_accepts_a_single_before_validation_hook_to_modify_data
    parse_array = proc do |data, property, property_schema, _|
      if data.key?(property) && property_schema.is_a?(Hash) && property_schema['type'] == 'array'
        parsed = data[property].split(',')
        parsed = parsed.map!(&:to_i) if property_schema['items']['type'] == 'integer'
        data[property] = parsed
      end
    end
    data = { 'list' => '1,2,3' }
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'integer' }
        }
      }
    }
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: parse_array
    ).valid?(data))
    assert_equal({'list' => [1, 2, 3]}, data)
  end

  def test_it_calls_before_validation_hooks_and_still_inserts_defaults
    replace_fake_with_peter = proc do |data, property, property_schema, _|
      data[property] = 'Peter' if property == 'name' && data[property] == 'fake'
    end
    data = [{ }, { 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      {
        'type' => 'array',
        'items' => {
          'type' => 'object',
          'properties' => {
            'name' => {
              'type' => 'string',
              'default' => 'fake'
            }
          }
        }
      },
      insert_property_defaults: true,
      before_property_validation: [replace_fake_with_peter]
    ).valid?(data))
    assert_equal([{ 'name' => 'Peter' }, { 'name' => 'Bob' }], data)
  end

  def test_it_calls_after_validation_hooks_to_modify_data
    convert_date = proc do |data, property, property_schema, _|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: [convert_date]
    )
    data = { 'start_date' => '2020-09-03' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3)}, data)
  end

  def test_it_accepts_a_single_proc_as_after_validation_hook
    convert_date = proc do |data, property, property_schema|
      if data[property] && property_schema.is_a?(Hash) && property_schema['format'] == 'date'
        data[property] = Date.iso8601(data[property])
      end
    end
    schema = {
      'properties' => {
        'start_date' => {
          'type' => 'string',
          'format' => 'date'
        }
      }
    }
    validator= JSONSchemer.schema(
      schema,
      after_property_validation: convert_date
    )
    data = { 'start_date' => '2020-09-03' }
    assert(validator.valid?(data))
    assert_equal({'start_date' => Date.new(2020, 9, 3)}, data)
  end

  def test_it_does_not_modify_passed_hooks_array
    schema = {
      'properties' => {
        'list' => {
          'type' => 'array',
          'items' => { 'type' => 'string' }
        }
      }
    }
    data = [{ 'name' => 'Bob' }]
    assert(JSONSchemer.schema(
      schema,
      before_property_validation: [proc {}].freeze,
      after_property_validation: [proc {}].freeze,
      insert_property_defaults: true
    ).valid?(data))
  end

  def test_it_does_not_fail_when_the_schema_is_completely_empty
    schema = {}
    data = {
      'a' => 1
    }
    assert(JSONSchemer.schema(schema).valid?(data))
    assert_equal({ 'a' => 1 }, data)
  end

  def test_it_allows_disabling_format
    schema = JSONSchemer.schema(
      { 'format' => 'email' },
      format: false
    )
    assert(schema.valid?('not-an-email'))
  end

  def test_it_ignores_format_for_invalid_type
    schema = JSONSchemer.schema({
      'format' => 'email'
    })
    refute(schema.valid?('not-an-email'))
    assert(schema.valid?({}))
  end

  def test_it_allows_false_custom_format
    schema = JSONSchemer.schema(
      {
        'type' => 'object',
        'properties' => {
          'one' => {
            'format' => 'email'
          },
          'two' => {
            'format' => 'time'
          }
        }
      },
      formats: {
        'email' => false
      }
    )
    data = {
      'one' => 'not-an-email',
      'two' => 'not-a-time'
    }
    errors = schema.validate(data).to_a
    assert_equal(1, errors.size)
    assert_equal('not-a-time', errors.first.fetch('data'))
    assert_equal('format', errors.first.fetch('type'))
  end

  def test_it_allows_callable_custom_format
    schema = JSONSchemer.schema(
      { 'format' => 'custom' },
      formats: {
        'custom' => proc { |x| x == 'valid' }
      }
    )
    assert(schema.valid?('valid'))
    refute(schema.valid?('invalid'))
  end

  def test_it_returns_correct_pointers_for_ref_pointer
    ref_schema = { 'type' => 'string' }
    root = {
      'definitions' => {
        'y' => ref_schema
      },
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => '#/definitions/y' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(root)
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => ref_schema,
        'schema_pointer' => '/definitions/y',
        'root_schema' => root,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_it_returns_correct_pointers_for_remote_ref_pointer
    ref_schema = { 'type' => 'string' }
    ref = {
      'definitions' => {
        'y' => ref_schema
      }
    }
    root = {
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => 'http://example.com/#/definitions/y' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(
      root,
      ref_resolver: proc { ref }
    )
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => ref_schema,
        'schema_pointer' => '/definitions/y',
        'root_schema' => ref,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_it_returns_correct_pointers_for_ref_id
    ref_schema = {
      '$id' => 'http://example.com/foo',
      'type' => 'string'
    }
    root = {
      'definitions' => {
        'y' => ref_schema
      },
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => 'http://example.com/foo' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(root)
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => ref_schema,
        'schema_pointer' => '/definitions/y',
        'root_schema' => root,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_can_refer_to_subschemas_inside_hashes
    root = {
     'foo' => {
        'bar' => {
          '$id' => '#bar',
          'type' => 'string'
        }
      },
      '$ref' => '#bar'
    }
    schema = JSONSchemer.schema(
      root
    )
    errors = schema.validate(42).to_a
    assert_equal(
      {
        'data' => 42,
        'data_pointer' => '',
        'schema' => root['foo']['bar'],
        'schema_pointer' => '/foo/bar',
        'root_schema' => root,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_can_refer_to_subschemas_inside_arrays
    root = {
     'foo' => [{
        'bar' => {
          '$id' => '#bar',
          'type' => 'string'
        }
      }],
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => '#bar' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(root)
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => root['foo'].first['bar'],
        'schema_pointer' => '/foo/0/bar',
        'root_schema' => root,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_can_refer_to_subschemas_in_hash_with_remote_pointer
    ref_schema = {
      '$id' => 'http://example.com/ref_schema.json',
      'foo' => {
        'bar' => {
          '$id' => '#bar',
          'type' => 'string'
        }
      }
    }
    root = {
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => 'http://example.com/ref_schema.json#bar' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(
      root,
      ref_resolver: proc { ref_schema }
    )
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => ref_schema['foo']['bar'],
        'schema_pointer' => '/foo/bar',
        'root_schema' => ref_schema,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_can_refer_to_multiple_subschemas_in_hash
    ref_schema = {
      '$id' => 'http://example.com/ref_schema.json',
      'types' => {
        'uuid' => {
           '$id' => "#uuid",
           'type' => 'string',
           'pattern' => "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }
      },
      'foo' => {
        'bar' => {
          '$id' => '#bar',
          'allOf' => [{ "$ref" => "#uuid"}]
        }
      }
    }
    root = {
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => 'http://example.com/ref_schema.json#bar' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(
      root,
      ref_resolver: proc { ref_schema }
    )
    errors = schema.validate({ 'a' => { 'x' => "1122-112" } }).to_a
    assert_equal(
      {
        'data' => "1122-112",
        'data_pointer' => '/a/x',
        'schema' => ref_schema['types']['uuid'],
        'schema_pointer' => '/types/uuid',
        'root_schema' => ref_schema,
        'type' => 'pattern'
      },
      errors.first
    )
  end

  def test_it_returns_correct_pointers_for_remote_ref_id
    ref_schema = {
      '$id' => 'http://example.com/remote-id',
      'type' => 'string'
    }
    ref = {
      'definitions' => {
        'y' => ref_schema
      }
    }
    root = {
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => 'http://example.com/remote-id' }
          }
        }
      }
    }
    schema = JSONSchemer.schema(
      root,
      ref_resolver: proc { ref }
    )
    errors = schema.validate({ 'a' => { 'x' => 1 } }).to_a
    assert_equal(
      {
        'data' => 1,
        'data_pointer' => '/a/x',
        'schema' => ref_schema,
        'schema_pointer' => '/definitions/y',
        'root_schema' => ref,
        'type' => 'string'
      },
      errors.first
    )
  end

  def test_it_returns_correct_pointers_for_items_array
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'items' => [
              { 'type' => 'integer' },
              { 'type' => 'string' }
            ]
          }
        }
      }
    )
    errors = schema.validate({ 'x' => ['wrong', 1] }).to_a
    assert_equal(['/x/0', '/properties/x/items/0'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/x/1', '/properties/x/items/1'], errors.last.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_additional_items
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'items' => [
              { 'type' => 'integer' }
            ],
            'additionalItems' => { 'type' => 'string' }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => ['wrong', 1] }).to_a
    assert_equal(['/x/0', '/properties/x/items/0'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/x/1', '/properties/x/additionalItems'], errors.last.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_items
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'items' => { 'type' => 'boolean' }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => ['wrong', 1] }).to_a
    assert_equal(['/x/0', '/properties/x/items'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/x/1', '/properties/x/items'], errors.last.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_dependencies
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'a' => {
            'dependencies' => {
              'x' => ['y'],
              'z' => { 'minProperties' => 10 }
            }
          }
        }
      }
    )
    errors = schema.validate({
      'a' => {
        'x' => 1,
        'z' => 2
      }
    }).to_a
    assert_equal(['/a', '/properties/a/dependencies/x'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/a', '/properties/a/dependencies/z'], errors.last.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_property_names
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'propertyNames' => { 'minLength' => 10 }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => { 'abc' => 1 } }).to_a
    assert_equal(['/x', '/properties/x/propertyNames'], errors.first.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_pattern_properties
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'patternProperties' => {
              '^a' => { 'type' => 'string' }
            }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => { 'abc' => 1 } }).to_a
    assert_equal(['/x/abc', '/properties/x/patternProperties/^a'], errors.first.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_additional_properties
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'additionalProperties' => { 'type' => 'string' }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => { 'abc' => 1 } }).to_a
    assert_equal(['/x/abc', '/properties/x/additionalProperties'], errors.first.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_raises_for_invalid_file_uris
    schemas = Pathname.new(__dir__).join('schemas')
    assert_raises(JSONSchemer::InvalidFileURI) { JSONSchemer.schema(schemas.join('file_uri_ref_invalid_host.json')).valid?({}) }
    assert_raises(JSONSchemer::InvalidFileURI) { JSONSchemer.schema(schemas.join('file_uri_ref_invalid_scheme.json')).valid?({}) }
  end

  def test_it_handles_pathnames
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'schema1.json'))
    assert_equal('required', schema.validate({ 'id' => 1 }).first.fetch('type'))
    assert_equal('required', schema.validate({ 'a' => 'abc' }).first.fetch('type'))
    assert_equal('string', schema.validate({ 'id' => 1, 'a' => 1 }).first.fetch('type'))
    assert(schema.valid?({ 'id' => 1, 'a' => 'abc' }))
  end

  def test_required_validation_adds_missing_keys
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'schema1.json'))
    error = schema.validate({ 'id' => 1 }).first
    assert_equal('required', error.fetch('type'))
    assert_equal({ 'missing_keys' => ['a'] }, error.fetch('details'))
  end

  def test_it_allows_custom_ref_resolver_with_pathnames
    count = 0
    schema = JSONSchemer.schema(
      Pathname.new(__dir__).join('schemas', 'schema1.json'),
      :ref_resolver => proc do |uri|
        count += 1
        true
      end
    )
    assert(schema.valid?({ 'id' => 1, 'a' => 'abc' }))
    assert_equal(2, count)
  end

  def test_it_raises_for_invalid_ref_resolution
    schema = JSONSchemer.schema(
      { '$ref' => 'http://example.com' },
      :ref_resolver => proc { |uri| nil }
    )
    assert_raises(JSONSchemer::InvalidRefResolution) { schema.valid?('value') }
  end

  def test_it_handles_json_strings
    schema = JSONSchemer.schema('{ "type": "integer" }')
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_it_checks_for_symbol_keys
    assert_raises(JSONSchemer::InvalidSymbolKey) { JSONSchemer.schema({ :type => 'integer' }) }
    schema = JSONSchemer.schema(
      { '$ref' => 'http://example.com' },
      :ref_resolver => proc do |uri|
        { :type => 'integer' }
      end
    )
    assert_raises(JSONSchemer::InvalidSymbolKey) { schema.valid?(1) }
  end

  def test_cached_ref_resolver
    schema = {
      'properties' => {
        'x' => { '$ref' => 'http://example.com/1' },
        'y' => { '$ref' => 'http://example.com/1' },
        'z' => { '$ref' => 'http://example.com/2' }
      }
    }
    data = { 'x' => '', 'y' => '', 'z' => '' }
    counts = Hash.new(0)
    ref_resolver = proc do |uri|
      counts[uri.to_s] += 1
      { 'type' => 'string' }
    end
    assert(JSONSchemer.schema(schema, :ref_resolver => ref_resolver).valid?(data))
    assert_equal(2, counts['http://example.com/1'])
    assert_equal(1, counts['http://example.com/2'])
    counts.clear
    assert(JSONSchemer.schema(schema, :ref_resolver => JSONSchemer::CachedRefResolver.new(&ref_resolver)).valid?(data))
    assert_equal(1, counts['http://example.com/1'])
    assert_equal(1, counts['http://example.com/2'])
  end

  def test_it_handles_regex_anchors
    schema = JSONSchemer.schema({ 'pattern' => '^foo$' })
    assert(schema.valid?('foo'))
    refute(schema.valid?(' foo'))
    refute(schema.valid?('foo '))
    refute(schema.valid?("foo\nfoo\nfoo"))

    schema = JSONSchemer.schema({ 'pattern' => '\Afoo\z' })
    assert(schema.valid?('Afooz'))
    refute(schema.valid?('foo'))
    refute(schema.valid?('Afoo'))
    refute(schema.valid?('fooz'))
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
    assert_equal(
      {
        'data' => 32,
        'data_pointer' => '/numberOfModules',
        'schema' => {
          'type' => 'integer',
          'maximum' => 37,
          'minimum' => 25
        },
        'schema_pointer' => '/properties/numberOfModules/allOf/1/not',
        'root_schema' => root,
        'type' => 'not'
      },
      schema.validate({ 'numberOfModules' => 32 }).first
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
        'type' => 'integer'
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
        'type' => 'oneOf'
      },
      schema.validate({ 'numberOfModules' => 8 }).first
    )
  end

  def test_it_handles_nested_refs
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'nested_ref1.json'))
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_it_handles_json_pointer_refs_with_special_characters
    schema = JSONSchemer.schema({
      'type' => 'object',
      'properties' => { 'foo' => { '$ref' => '#/definitions/~1some~1{id}'} },
      'definitions' => { '/some/{id}' => { 'type' => 'string' } }
    })
    assert(schema.valid?({ 'foo' => 'bar' }))
    refute(schema.valid?({ 'foo' => 1 }))
  end

  def test_it_handles_spaces_in_schema_path
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'sp ce', 'sp ce.json'))
    assert schema.valid?('yes')
    refute schema.valid?(0)
  end

  def test_json_schema_test_suite
    {
      'draft4' => JSONSchemer::Schema::Draft4,
      'draft6' => JSONSchemer::Schema::Draft6,
      'draft7' => JSONSchemer::Schema::Draft7
    }.each do |version, draft_class|
      output = Dir["JSON-Schema-Test-Suite/tests/#{version}/**/*.json"].each_with_object({}) do |file, file_output|
        file_output[file] = JSON.parse(File.read(file)).map do |defn|
          defn.fetch('tests').map do |test|
            errors = draft_class.new(
              defn.fetch('schema'),
              ref_resolver: proc do |uri|
                # Resolve localhost test schemas
                if uri.host == 'localhost'
                  path = Pathname.new(__dir__).join('..', 'JSON-Schema-Test-Suite', 'remotes', uri.path.gsub(/\A\//, ''))
                  JSON.parse(path.read)
                else
                  response = Net::HTTP.get_response(uri)
                  if response.is_a?(Net::HTTPRedirection)
                    response = Net::HTTP.get_response(URI.parse(response.fetch('location')))
                  end
                  JSON.parse(response.body)
                end
              end
            ).validate(test.fetch('data')).to_a
            if test.fetch('valid')
              assert_empty(errors, file)
            else
              refute_empty(errors, file)
            end
            errors
          end
        end
      end
      fixture = Pathname.new(__dir__).join('fixtures', "#{version}.json")
      if ENV['WRITE_FIXTURES'] == 'true'
        fixture.write("#{JSON.pretty_generate(output)}\n")
      else
        assert_equal(output, JSON.parse(fixture.read))
      end
    end
  end

  def test_it_validates_correctly_custom_keywords
    root = {
      'type' => 'number',
      'even' => true
    }
    options = {
      keywords: {
        'even' => lambda do |data, curr_schema, _pointer|
          if curr_schema['even']
            data.to_i.even?
          else
            data.to_i.odd?
          end
        end
      }
    }

    schema = JSONSchemer.schema(root, **options)
    assert(schema.valid?(2))
    refute(schema.valid?(3))
  end

  def test_it_handles_multiple_of_floats
    assert(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.61))
    refute(JSONSchemer.schema({ 'multipleOf' => 0.01 }).valid?(8.666))
    assert(JSONSchemer.schema({ 'multipleOf' => 0.001 }).valid?(8.666))
  end
end
