require 'test_helper'

class RefTest < Minitest::Test
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
    schemer = JSONSchemer.schema({ '$ref' => 'http://json-schema.org/draft-07/schema#' }, :ref_resolver => 'net/http')
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
end
