require 'test_helper'

class FormatTest < Minitest::Test
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

  def test_it_ignores_unknown_format
    schemer = JSONSchemer.schema({ 'type' => 'string', 'format' => 'unknown' })
    assert(schemer.valid?('1'))
    refute(schemer.valid?(1))
    schemer = JSONSchemer.schema({ 'maximum' => 1, 'format' => 'unknown' })
    assert(schemer.valid?(1))
    refute(schemer.valid?(2))
  end

  def test_format_assertion_raises_unknown_format
    annotation = {
      '$vocabulary' => {
        'https://json-schema.org/draft/2020-12/vocab/format-annotation' => true
      }
    }
    assertion = {
      '$vocabulary' => {
        'https://json-schema.org/draft/2020-12/vocab/format-assertion' => true
      }
    }
    schema = {
      '$schema' => 'http://example.com',
      'format' => 'unknown'
    }
    assert(JSONSchemer.schema(schema, :ref_resolver => proc { annotation }).valid?('x'))
    assert_raises(JSONSchemer::UnknownFormat) { JSONSchemer.schema(schema, :ref_resolver => proc { assertion }) }
  end

  def test_it_validates_spaces_in_uri_format
    schema = JSONSchemer.schema({ 'format' => 'uri' })
    refute(schema.valid?('http://example.com?sp ce'))
    refute(schema.valid?('mailto:sp ce@example.com'))
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

  def test_email_format
    schema = JSONSchemer.schema({ 'format' => 'email' })

    {
      "joe.bloggs@example.com" => true,
      "2962" => false,
      "te~st@example.com" => true,
      "~test@example.com" => true,
      "test~@example.com" => true,
      "\"joe bloggs\"@example.com" => true,
      "\"joe..bloggs\"@example.com" => true,
      "\"joe@bloggs\"@example.com" => true,
      "joe.bloggs@[127.0.0.1]" => true,
      "joe.bloggs@[IPv6:::1]" => true,
      ".test@example.com" => false,
      "test.@example.com" => false,
      "te.s.t@example.com" => true,
      "te..st@example.com" => false,
      "joe.bloggs@invalid=domain.com" => false,
      "joe.bloggs@[127.0.0.300]" => false
    }.each do |email, valid|
      assert_equal(valid, schema.valid?(email))
    end
  end
end
