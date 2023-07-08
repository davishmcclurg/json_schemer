require 'test_helper'

class PointersTest < Minitest::Test
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
            'prefixItems' => [
              { 'type' => 'integer' },
              { 'type' => 'string' }
            ]
          }
        }
      }
    )
    errors = schema.validate({ 'x' => ['wrong', 1] }).to_a
    assert_equal(['/x/0', '/properties/x/prefixItems/0'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/x/1', '/properties/x/prefixItems/1'], errors.last.values_at('data_pointer', 'schema_pointer'))
  end

  def test_it_returns_correct_pointers_for_additional_items
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'x' => {
            'prefixItems' => [
              { 'type' => 'integer' }
            ],
            'items' => { 'type' => 'string' }
          }
        }
      }
    )
    errors = schema.validate({ 'x' => ['wrong', 1] }).to_a
    assert_equal(['/x/0', '/properties/x/prefixItems/0'], errors.first.values_at('data_pointer', 'schema_pointer'))
    assert_equal(['/x/1', '/properties/x/items'], errors.last.values_at('data_pointer', 'schema_pointer'))
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
    assert_equal(['/a', '/properties/a'], errors.first.values_at('data_pointer', 'schema_pointer'))
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
end
