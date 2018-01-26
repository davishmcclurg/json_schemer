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

  {
    'draft7' => JSONSchemer::Schema::Draft7
  }.each do |version, draft_class|
    Dir["JSON-Schema-Test-Suite/tests/#{version}/**/*.json"].each_with_index do |file, index|
      define_method("test_json_schema_test_suite_#{version}_#{index}") do
        JSON.parse(File.read(file)).each do |defn|
          defn.fetch('tests').each do |test|
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
