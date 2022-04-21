require 'test_helper'

class PrettyErrorsTest < Minitest::Test
  def test_required_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => { 'type' => 'string' }
        },
        'required' => %w[one]
      }
    )
    error = schema.validate({ 'two' => 'optional' }).to_a.first
    assert_equal("root is missing required keys: one", JSONSchemer::Errors.pretty(error))
  end

  def test_basic_type_message
    %w[string integer number boolean null object].each do |type|
      schema = JSONSchemer.schema(
        {
          'properties' => {
            'one' => { 'type' => type }
          }
        }
      )
      error = schema.validate({ 'one' => ['wrong'] }).to_a.first
      assert_equal("property '/one' is not of type: #{type}", JSONSchemer::Errors.pretty(error))
    end
  end

  def test_array_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => { 'type' => 'array' }
        }
      }
    )
    error = schema.validate({ 'one' => 'wrong' }).to_a.first
    assert_equal("property '/one' is not of type: array", JSONSchemer::Errors.pretty(error))
  end

  def test_format_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => {
            'type' => 'string',
            'format' => 'date-time'
          }
        }
      }
    )
    error = schema.validate({ 'one' => 'abc' }).to_a.first
    assert_equal("property '/one' does not match format: date-time", JSONSchemer::Errors.pretty(error))
  end

  def test_pattern_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => {
            'type' => 'string',
            'pattern' => '\d+'
          }
        }
      }
    )
    error = schema.validate({ 'one' => 'abc' }).to_a.first
    assert_equal("property '/one' does not match pattern: \\d+", JSONSchemer::Errors.pretty(error))
  end

  def test_enum_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => {
            'type' => 'string',
            'enum' => %w[one two]
          }
        }
      }
    )
    error = schema.validate({ 'one' => 'abc' }).to_a.first
    assert_equal("property '/one' is not one of: [\"one\", \"two\"]", JSONSchemer::Errors.pretty(error))
  end

  def test_const_message
    schema = JSONSchemer.schema(
      {
        'properties' => {
          'one' => {
            'type' => 'string',
            'const' => 'one'
          }
        }
      }
    )
    error = schema.validate({ 'one' => 'abc' }).to_a.first
    assert_equal("property '/one' is not: \"one\"", JSONSchemer::Errors.pretty(error))
  end
end
