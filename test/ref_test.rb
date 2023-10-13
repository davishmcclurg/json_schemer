require 'test_helper'

class RefTest < Minitest::Test
  def test_can_refer_to_subschemas_inside_hashes
    root = {
     'definitions' => {
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
        'schema' => root['definitions']['bar'],
        'schema_pointer' => '/definitions/bar',
        'root_schema' => root,
        'type' => 'string',
        'error' => 'value at root is not a string'
      },
      errors.first
    )
  end

  def test_can_refer_to_subschemas_inside_arrays
    root = {
     'allOf' => [{
        'if' => {
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
        'schema' => root['allOf'].first['if'],
        'schema_pointer' => '/allOf/0/if',
        'root_schema' => root,
        'type' => 'string',
        'error' => 'value at `/a/x` is not a string'
      },
      errors.first
    )
  end

  def test_can_json_pointer_refer_to_subschemas_inside_unknown_arrays
    root = {
      'unknown' => [{ 'type' => 'string' }],
      'properties' => {
        'a' => {
          'properties' => {
            'x' => { '$ref' => '#/unknown/0' }
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
        'schema' => root['unknown'].first,
        'schema_pointer' => '/unknown/0',
        'root_schema' => root,
        'type' => 'string',
        'error' => 'value at `/a/x` is not a string'
      },
      errors.first
    )
  end

  def test_invalid_ref_pointer
    root = {
      '$ref' => '#/unknown/beyond',
      'unknown' => 'notahash'
    }
    schema = JSONSchemer.schema(root)
    assert_raises(JSONSchemer::InvalidRefPointer) { schema.validate({}) }
  end

  def test_can_refer_to_subschemas_in_hash_with_remote_pointer
    ref_schema = {
      '$id' => 'http://example.com/ref_schema.json',
      'definitions' => {
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
        'schema' => ref_schema['definitions']['bar'],
        'schema_pointer' => '/definitions/bar',
        'root_schema' => ref_schema,
        'type' => 'string',
        'error' => 'value at `/a/x` is not a string'
      },
      errors.first
    )
  end

  def test_can_refer_to_multiple_subschemas_in_hash
    ref_schema = {
      '$id' => 'http://example.com/ref_schema.json',
      'definitions' => {
        'uuid' => {
           '$id' => "#uuid",
           'type' => 'string',
           'pattern' => "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$"
        }
      },
      'not' => {
        '$id' => '#bar',
        'allOf' => [{ "$ref" => "#uuid"}]
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
        'schema' => ref_schema['definitions']['uuid'],
        'schema_pointer' => '/definitions/uuid',
        'root_schema' => ref_schema,
        'type' => 'pattern',
        'error' => 'string at `/a/x` does not match pattern: ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      },
      errors.first
    )
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
    counts.clear
    assert(JSONSchemer.schema(schema, :ref_resolver => JSONSchemer::CachedResolver.new(&ref_resolver)).valid?(data))
    assert_equal(1, counts['http://example.com/1'])
    assert_equal(1, counts['http://example.com/2'])
  end

  def test_net_http_ref_resolver
    schemer = JSONSchemer.schema({ '$ref' => 'https://json-schema.org/draft/2020-12/schema' }, :ref_resolver => 'net/http')
    assert(schemer.valid?({ 'type' => 'string' }))
    refute(schemer.valid?({ 'type' => 1 }))
  end

  def test_it_handles_nested_refs
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'nested_ref1.json'))
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_it_handles_json_pointer_refs_with_special_characters
    schema = JSONSchemer.schema({
      'type' => 'object',
      'properties' => { 'foo' => { '$ref' => '#/definitions/~1some~1%7Bid%7D'} },
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

  def test_it_handles_windows_paths
    schema = JSONSchemer.schema(Pathname.new(__dir__).join('schemas', 'windows_path.json'))
    read = proc do |path|
      assert_equal('c:/not/a/real/path', path)
      '{ "type": "string" }'
    end
    File.stub(:read, read) do
      assert(schema.valid?('1'))
      refute(schema.valid?(1))
    end
  end

  def test_it_handles_base_uri_change_folder
    schema = JSONSchemer.schema(
      {
        '$id' => 'http://localhost:1234/draft2019-09/scope_change_defs1.json',
        'type' => 'object',
        'definitions' => {
          'baz' => {
            '$id' => 'baseUriChangeFolder/',
            'type' => 'array',
            'items' => {
              '$ref' => 'folderInteger.json'
            }
          }
        },
        'properties' => {
          'list' => {
            '$ref' => 'baseUriChangeFolder/'
          }
        }
      },
      :ref_resolver => proc do |uri|
        assert_equal(URI('http://localhost:1234/draft2019-09/baseUriChangeFolder/folderInteger.json'), uri)
        '{ "type": "integer" }'
      end
    )
    assert(schema.valid?({ 'list' => [1] }))
    refute(schema.valid?({ 'list' => ['a'] }))
  end

  def test_it_handles_base_uri_change_folder_in_subschema
    schema = JSONSchemer.schema(
      {
        '$id' => 'http://localhost:1234/draft2019-09/scope_change_defs2.json',
        'type' => 'object',
        'definitions' => {
          'baz' => {
            '$id' => 'baseUriChangeFolderInSubschema/',
            'definitions' => {
              'bar' => {
                'type' => 'array',
                'items' => {
                  '$ref' => 'folderInteger.json'
                }
              }
            }
          }
        },
        'properties' => {
          'list' => {
            '$ref' => 'baseUriChangeFolderInSubschema/#/definitions/bar'
          }
        }
      },
      :ref_resolver => proc do |uri|
        assert_equal(URI('http://localhost:1234/draft2019-09/baseUriChangeFolderInSubschema/folderInteger.json'), uri)
        '{ "type": "integer" }'
      end
    )
    assert(schema.valid?({ 'list' => [1] }))
    refute(schema.valid?({ 'list' => ['a'] }))
  end

  def test_it_handles_relative_base_uri_json_pointer_ref
    refs = {
      'relative' => {
        'definitions' => {
          'foo' => {
            'type' => 'integer'
          }
        },
        'properties' => {
          'bar' => {
            '$ref' => '#/definitions/foo'
          }
        }
      }
    }
    schema = JSONSchemer.schema(
      { '$ref' => 'relative' },
      :ref_resolver => proc { |uri| refs[uri.path.delete_prefix('/')] }
    )
    assert(schema.valid?({ 'bar' => 1 }))
    refute(schema.valid?({ 'bar' => '1' }))
  end

  def test_exclusive_ref_supports_definitions
    schema = JSONSchemer.schema({
      '$schema' => 'http://json-schema.org/draft-07/schema#',
      '$ref' => '#yah',
      'definitions' => {
        'yah' => {
          '$id' => '#yah',
          'type' => 'integer'
        }
      }
    })
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end

  def test_exclusive_ref_supports_definitions_with_id_and_json_pointer
    schema = JSONSchemer.schema({
      '$schema' => 'http://json-schema.org/draft-07/schema#',
      '$id' => 'https://example.com/schema',
      '$ref' => '#/definitions/yah',
      'definitions' => {
        'yah' => {
          '$id' => '#yah',
          'type' => 'integer'
        }
      }
    })
    assert(schema.valid?(1))
    refute(schema.valid?('1'))
  end
end
