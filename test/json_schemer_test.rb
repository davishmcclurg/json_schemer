require 'test_helper'
require 'json'

class JSONSchemerTest < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::JSONSchemer::VERSION
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
    assert schema.valid?(data)
    errors = schema.validate(data)
    assert errors.none?
  end

  def test_it_allows_disabling_format
    schema = JSONSchemer.schema(
      { 'format' => 'email' },
      format: false
    )
    assert schema.valid?('not-an-email')
  end

  def test_it_ignores_format_for_invalid_type
    schema = JSONSchemer.schema({
      'format' => 'email'
    })
    refute schema.valid?('not-an-email')
    assert schema.valid?({})
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
    assert errors.size == 1
    assert errors.first.fetch('data') == 'not-a-time'
    assert errors.first.fetch('type') == 'format'
  end

  def test_it_allows_callable_custom_format
    schema = JSONSchemer.schema(
      { 'format' => 'custom' },
      formats: {
        'custom' => proc { |x| x == 'valid' }
      }
    )
    assert schema.valid?('valid')
    refute schema.valid?('invalid')
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
    assert errors.first == {
      'data' => 1,
      'data_pointer' => '/a/x',
      'schema' => ref_schema,
      'schema_pointer' => '/definitions/y',
      'root_schema' => root,
      'type' => 'string'
    }
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
    assert errors.first == {
      'data' => 1,
      'data_pointer' => '/a/x',
      'schema' => ref_schema,
      'schema_pointer' => '/definitions/y',
      'root_schema' => ref,
      'type' => 'string'
    }
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
    assert errors.first == {
      'data' => 1,
      'data_pointer' => '/a/x',
      'schema' => ref_schema,
      'schema_pointer' => '/definitions/y',
      'root_schema' => root,
      'type' => 'string'
    }
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
    assert errors.first == {
      'data' => 1,
      'data_pointer' => '/a/x',
      'schema' => ref_schema,
      'schema_pointer' => '/definitions/y',
      'root_schema' => ref,
      'type' => 'string'
    }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/0', 'schema_pointer' => '/properties/x/items/0' }
    assert errors.last.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/1', 'schema_pointer' => '/properties/x/items/1' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/0', 'schema_pointer' => '/properties/x/items/0' }
    assert errors.last.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/1', 'schema_pointer' => '/properties/x/additionalItems' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/0', 'schema_pointer' => '/properties/x/items' }
    assert errors.last.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/1', 'schema_pointer' => '/properties/x/items' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/a', 'schema_pointer' => '/properties/a/dependencies/x' }
    assert errors.last.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/a', 'schema_pointer' => '/properties/a/dependencies/z' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x', 'schema_pointer' => '/properties/x/propertyNames' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/abc', 'schema_pointer' => '/properties/x/patternProperties/^a' }
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
    assert errors.first.slice('data_pointer', 'schema_pointer') == { 'data_pointer' => '/x/abc', 'schema_pointer' => '/properties/x/additionalProperties' }
  end

  {
    'draft4' => JSONSchemer::Schema::Draft4,
    'draft6' => JSONSchemer::Schema::Draft6,
    'draft7' => JSONSchemer::Schema::Draft7
  }.each do |version, draft_class|
    Dir["JSON-Schema-Test-Suite/tests/#{version}/**/*.json"].each_with_index do |file, file_index|
      JSON.parse(File.read(file)).each_with_index do |defn, defn_index|
        defn.fetch('tests').each_with_index do |test, test_index|
          define_method("test_json_schema_test_suite_#{version}_#{file_index}_#{defn_index}_#{test_index}") do
            errors = begin
              draft_class.new(
                defn.fetch('schema'),
                ref_resolver: 'net/http'
              ).validate(test.fetch('data')).to_a
            rescue StandardError, NotImplementedError => e
              [e.class, e.message]
            end
            if test.fetch('valid')
              assert_empty(errors, file)
            else
              assert(errors.any?, file)
            end
          end
        end
      end
    end
  end
end
