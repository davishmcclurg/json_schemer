require 'test_helper'

class OutputFormatTest < Minitest::Test
  def test_output_formats_match_specification_examples
    schemer = JSONSchemer.schema({
      '$id' => 'https://example.com/polygon',
      '$schema' => 'https://json-schema.org/draft/2020-12/schema',
      '$defs' => {
        'point' => {
          'type' => 'object',
          'properties' => {
            'x' => { 'type' => 'number' },
            'y' => { 'type' => 'number' }
          },
          'additionalProperties' => false,
          'required' => [ 'x', 'y' ]
        }
      },
      'type' => 'array',
      'items' => { '$ref' => '#/$defs/point' },
      'minItems' => 3
    })

    instance = [
      {
        'x' => 2.5,
        'y' => 1.3
      },
      {
        'x' => 1,
        'z' => 6.7
      }
    ]

    assert_equal(
      { 'valid' => false },
      schemer.validate(instance, :output_format => 'flag')
    )

    assert_equal(
      {
        'valid' => false,
        'keywordLocation' => '', # not in spec
        'absoluteKeywordLocation' => 'https://example.com/polygon#', # not in spec
        'instanceLocation' => '', # not in spec
        'error' => 'value at root does not match schema', # not in spec
        # out of order
        'errors' => [
          {
            'valid' => false, # not in spec
            'keywordLocation' => '',
            'absoluteKeywordLocation' => 'https://example.com/polygon#', # not in spec
            'instanceLocation' => '',
            'error' => 'value at root does not match schema' # 'A subschema had errors.'
          },
          {
            'valid' => false, # not in spec
            'keywordLocation' => '/items/$ref',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point',
            'instanceLocation' => '/1',
            'error' => 'value at `/1` does not match schema' # 'A subschema had errors.'
          },
          {
            'valid' => false, # not in spec
            'keywordLocation' => '/items/$ref/additionalProperties',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point/additionalProperties',
            'instanceLocation' => '/1/z',
            'error' => 'object property at `/1/z` is not defined and schema does not allow additional properties' # 'Additional property \'z\' found but was invalid.'
          },
          {
            'valid' => false, # not in spec
            'keywordLocation' => '/items/$ref/required',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point/required',
            'instanceLocation' => '/1',
            'error' => 'object at `/1` is missing required properties: y' # 'Required property \'y\' not found.'
          },
          {
            'valid' => false, # not in spec
            'keywordLocation' => '/minItems',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/minItems', # not in spec
            'instanceLocation' => '',
            'error' => 'array size at root is less than: 3', # 'Expected at least 3 items but found 2'
          }
        ]
      },
      schemer.validate(instance, :output_format => 'basic', :resolve_enumerators => true)
    )

    assert_equal(
      {
        'valid' => false,
        'keywordLocation' => '',
        'absoluteKeywordLocation' => 'https://example.com/polygon#', # not in spec
        'instanceLocation' => '',
        'error' => 'value at root does not match schema', # not in spec
        'errors' => [
          {
            'valid' => false,
            'keywordLocation' => '/items/$ref',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point',
            'instanceLocation' => '/1',
            'error' => 'value at `/1` does not match schema', # not in spec
            # out of order
            'errors' => [
              {
                'valid' => false,
                'keywordLocation' => '/items/$ref/additionalProperties',
                'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point/additionalProperties',
                'instanceLocation' => '/1/z',
                'error' => 'object property at `/1/z` is not defined and schema does not allow additional properties' # 'Additional property \'z\' found but was invalid.'
              },
              {
                'valid' => false,
                'keywordLocation' => '/items/$ref/required',
                'absoluteKeywordLocation' => 'https://example.com/polygon#/$defs/point/required',
                'instanceLocation' => '/1',
                'error' => 'object at `/1` is missing required properties: y' # 'Required property \'y\' not found.'
              }
            ]
          },
          {
            'valid' => false,
            'keywordLocation' => '/minItems',
            'absoluteKeywordLocation' => 'https://example.com/polygon#/minItems', # not in spec
            'instanceLocation' => '',
            'error' => 'array size at root is less than: 3' # 'Expected at least 3 items but found 2'
          }
        ]
      },
      schemer.validate(instance, :output_format => 'detailed', :resolve_enumerators => true)
    )
  end

  def test_it_escapes_absolute_keyword_location
    pattern = '^(a[b]{2}c|#%z\\"<>`|[\\-_.!~*\'();/?:@&=+$,])'
    schema = {
      '$id' => 'https://example.com',
      'patternProperties' => {
        pattern => {
          'not' => {
            'const' => 'xyz'
          }
        }
      }
    }
    schemer = JSONSchemer.schema(schema)

    output = schemer.validate({ 'abbc' => 'xyz' }, :output_format => 'basic')
    absolute_keyword_location = output.fetch('errors').first.fetch('absoluteKeywordLocation')

    assert_equal(
      'https://example.com#/patternProperties/%5E(a%5Bb%5D%7B2%7Dc%7C%23%25z%5C%22%3C%3E%60%7C%5B%5C-_.!~0*\'();~1?:@&=+$,%5D)/not',
      absolute_keyword_location
    )

    uri = URI(absolute_keyword_location)
    json_pointer = URI::DEFAULT_PARSER.unescape(uri.fragment)
    assert_equal(
      '/patternProperties/^(a[b]{2}c|#%z\\"<>`|[\\-_.!~0*\'();~1?:@&=+$,])/not',
      json_pointer
    )

    assert_equal(
      { 'const' => 'xyz' },
      Hana::Pointer.new(json_pointer).eval(schema)
    )
  end

  # tests:
  # - keyword_location with $ref and $dynamicRef
  # - absolute_keyword_location uses nearest $id and json pointer
  def test_output_formats
    subschema1 = {
      'minProperties' => 1
    }
    subschema2 = {
      '$dynamicAnchor' => 'two',
      'properties' => {
        'a' => {
          '$dynamicRef' => '#two',
          'maxProperties' => 2
        }
      }
    }
    schema = {
      '$id' => 'https://example.com/schema/',
      'allOf' => [
        { 'type' => 'object' },
        { '$ref' => 'subschema1' },
        { '$ref' => 'subschema2' }
      ],
      '$defs' => {
        'def1' => {
          '$dynamicAnchor' => 'two',
          'allOf' => [
            {
              '$id' => 'bee',
              'properties' => {
                'b' => { 'type' => 'string' }
              }
            }
          ]
        }
      }
    }
    refs = {
      URI('https://example.com/schema/subschema1') => subschema1,
      URI('https://example.com/schema/subschema2') => subschema2
    }
    schemer = JSONSchemer.schema(schema, :ref_resolver => refs.to_proc)
    instance = { 'a' => { 'a' => {}, 'b' => {}, 'c' => {} } }

    assert_equal(
      { 'valid' => false },
      schemer.validate(instance, :output_format => 'flag')
    )

    assert_equal(
      {
        'valid' => false,
        'keywordLocation' => '',
        'absoluteKeywordLocation' => 'https://example.com/schema/#',
        'instanceLocation' => '',
        'error' => 'value at root does not match schema',
        'errors' => [
          {
            'valid' => false,
            'keywordLocation' => '/allOf/2/$ref/properties/a',
            'absoluteKeywordLocation' => 'https://example.com/schema/subschema2#/properties/a',
            'instanceLocation' => '/a',
            'error' => 'value at `/a` does not match schema'
          },
          {
            'valid' => false,
            'keywordLocation' => '/allOf/2/$ref/properties/a/$dynamicRef/allOf/0/properties/b/type',
            'absoluteKeywordLocation' => 'https://example.com/schema/bee#/properties/b/type',
            'instanceLocation' => '/a/b',
            'error' => 'value at `/a/b` is not a string'
          },
          {
            'valid' => false,
            'keywordLocation' => '/allOf/2/$ref/properties/a/maxProperties',
            'absoluteKeywordLocation' => 'https://example.com/schema/subschema2#/properties/a/maxProperties',
            'instanceLocation' => '/a',
            'error' => 'object size at `/a` is greater than: 2'
          }
        ]
      },
      schemer.validate(instance, :output_format => 'basic', :resolve_enumerators => true)
    )

    assert_equal(
      {
        'valid' => false,
        'keywordLocation' => '/allOf/2/$ref/properties/a',
        'absoluteKeywordLocation' => 'https://example.com/schema/subschema2#/properties/a',
        'instanceLocation' => '/a',
        'error' => 'value at `/a` does not match schema',
        'errors' => [
          {
            'valid' => false,
            'keywordLocation' => '/allOf/2/$ref/properties/a/$dynamicRef/allOf/0/properties/b/type',
            'absoluteKeywordLocation' => 'https://example.com/schema/bee#/properties/b/type',
            'instanceLocation' => '/a/b',
            'error' => 'value at `/a/b` is not a string'
          },
          {
            'valid' => false,
            'keywordLocation' => '/allOf/2/$ref/properties/a/maxProperties',
            'absoluteKeywordLocation' => 'https://example.com/schema/subschema2#/properties/a/maxProperties',
            'instanceLocation' => '/a',
            'error' => 'object size at `/a` is greater than: 2'
          }
        ]
      },
      schemer.validate(instance, :output_format => 'detailed', :resolve_enumerators => true)
    )
  end
end
