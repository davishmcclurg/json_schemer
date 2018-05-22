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
                :ref_resolver => 'net/http'
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
