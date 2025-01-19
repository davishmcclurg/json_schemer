require 'test_helper'

class ConfigurationTest < Minitest::Test
  def run_configuration_test(option, test:, default: (skip_default = true))
    original = JSONSchemer.configuration.public_send(option)

    if default.nil?
      assert_nil(original)
    elsif default.respond_to?(:call)
      default.call(original)
    elsif !skip_default
      assert_equal(default, original)
    end

    JSONSchemer.configure { |config| config.public_send("#{option}=", test) }

    yield if block_given?

    assert_equal(test, JSONSchemer.configuration.public_send(option))

    # We need to reset the configuration to avoid "polluting" other tests.
    JSONSchemer.configure { |config| config.public_send("#{option}=", original) }
  end

  def test_configure
    JSONSchemer.configure do |config|
      assert_instance_of(JSONSchemer::Configuration, config)
    end
  end

  def test_base_uri
    run_configuration_test(
      :base_uri,
      default: URI('json-schemer://schema'),
      test: URI('some-other://schema')
    )
  end

  def test_meta_schema
    run_configuration_test(
      :meta_schema,
      default: 'https://json-schema.org/draft/2020-12/schema',
      test: JSONSchemer.draft201909
    )
  end

  def test_string_meta_schema
    run_configuration_test(:meta_schema, test: 'https://json-schema.org/draft/2019-09/schema') do
      assert_equal(JSONSchemer.draft201909, JSONSchemer.schema({ 'maximum' => 1 }).meta_schema)
      assert(JSONSchemer.schema({ 'maximum' => 1 }).valid?(1))
      refute(JSONSchemer.schema({ 'exclusiveMaximum' => 1 }).valid?(1))
      assert(JSONSchemer.valid_schema?({ 'exclusiveMaximum' => 1  }))
      refute(JSONSchemer.valid_schema?({ 'maximum' => 1, 'exclusiveMaximum' => true  }))
    end
    run_configuration_test(:meta_schema, test: 'http://json-schema.org/draft-04/schema#') do
      assert_equal(JSONSchemer.draft4, JSONSchemer.schema({ 'maximum' => 1 }).meta_schema)
      assert(JSONSchemer.schema({ 'maximum' => 1 }).valid?(1))
      refute(JSONSchemer.schema({ 'maximum' => 1, 'exclusiveMaximum' => true }).valid?(1))
      refute(JSONSchemer.valid_schema?({ 'exclusiveMaximum' => 1  }))
      assert(JSONSchemer.valid_schema?({ 'maximum' => 1, 'exclusiveMaximum' => true  }))
    end
  end

  def test_vocabulary
    run_configuration_test(
      :vocabulary,
      default: nil,
      test: { 'json-schemer://draft4' => true }
    )
  end

  def test_format
    run_configuration_test(
      :format,
      default: true,
      test: false
    )
  end

  def test_formats
    run_configuration_test(
      :formats,
      default: {},
      test: {
        'some-format' => lambda { |instance, _format| true }
      }
    )
  end

  def test_content_encodings
    run_configuration_test(
      :content_encodings,
      default: {},
      test: {
        'lowercase' => lambda { |instance| [true, instance&.downcase] }
      }
    )
  end

  def test_content_media_types
    run_configuration_test(
      :content_media_types,
      default: {},
      test: {
        'text/csv' => lambda do |instance|
          [true, CSV.parse(instance)]
        rescue
          [false, nil]
        end
      }
    )
  end

  def test_keywords
    run_configuration_test(
      :keywords,
      default: {},
      test: {
        'even' => lambda { |data, curr_schema, _pointer| curr_schema.fetch('even') == data.to_i.even? }
      }
    )
  end

  def test_before_property_validation
    run_configuration_test(
      :before_property_validation,
      default: [],
      test: ['something']
    )
  end

  def test_after_property_validation
    run_configuration_test(
      :after_property_validation,
      default: [],
      test: ['something']
    )
  end

  def test_insert_property_defaults
    run_configuration_test(
      :insert_property_defaults,
      default: false,
      test: true
    )
  end

  def test_property_default_resolver
    run_configuration_test(
      :property_default_resolver,
      default: nil,
      test: lambda { |instance, property, results_with_tree_validity| true }
    )
  end

  def test_ref_resolver
    run_configuration_test(
      :ref_resolver,
      default: lambda do |ref_resolver|
        assert_raises(JSONSchemer::UnknownRef) do
          ref_resolver.call(URI('example'))
        end
      end,
      test: lambda { |uri| { 'type' => 'string' } }
    )
  end

  def test_regexp_resolver
    run_configuration_test(
      :regexp_resolver,
      default: 'ruby',
      test: 'ecma'
    )
  end

  def test_output_format
    run_configuration_test(
      :output_format,
      default: 'classic',
      test: 'basic'
    )
  end

  def test_resolve_enumerators
    run_configuration_test(
      :resolve_enumerators,
      default: false,
      test: true
    )
  end

  def test_access_mode
    run_configuration_test(
      :access_mode,
      default: nil,
      test: "write"
    )
  end

  def test_configuration_option_and_override
    configuration = JSONSchemer::Configuration.new
    configuration.format = false
    assert(JSONSchemer.schema({ 'format' => 'time' }).valid?('08:30:06Z'))
    refute(JSONSchemer.schema({ 'format' => 'time' }).valid?('X'))
    assert(JSONSchemer.schema({ 'format' => 'time' }, configuration: configuration).valid?('08:30:06Z'))
    assert(JSONSchemer.schema({ 'format' => 'time' }, configuration: configuration).valid?('X'))
    assert(JSONSchemer.schema({ 'format' => 'time' }, configuration: configuration, format: true).valid?('08:30:06Z'))
    refute(JSONSchemer.schema({ 'format' => 'time' }, configuration: configuration, format: true).valid?('X'))
  end

  def test_configuration_keyword_init
    configuration = JSONSchemer::Configuration.new(:format => false)
    refute(JSONSchemer.schema({ 'format' => 'time' }).valid?('X'))
    assert(JSONSchemer.schema({ 'format' => 'time' }, configuration: configuration).valid?('X'))
  end

  def test_configuration_behavior
    before_property_validation = false
    after_property_validation = false

    configuration = JSONSchemer::Configuration.new(
      base_uri: URI('json-schemer://testschema'),
      meta_schema: 'http://json-schema.org/draft-07/schema#',
      formats: {
        'custom-format' => proc do |instance, _value|
          instance == 'valid-format'
        end
      },
      content_encodings: {
        'custom-content-encoding' => proc do |instance|
          [instance == 'valid-content-encoding', 'valid-content-encoding']
        end
      },
      content_media_types: {
        'custom-media-type' => proc do |instance|
          [instance == 'valid-media-type', 'valid-media-type']
        end
      },
      keywords: {
        'custom-keyword' => proc do |instance, _schema, _instance_location|
          instance == 'valid-keyword'
        end
      },
      before_property_validation: proc { before_property_validation = true },
      after_property_validation: [proc { after_property_validation = true }],
      insert_property_defaults: true,
      property_default_resolver: proc do |instance, property, _results_with_tree_validity|
        instance[property] = 'custom-default'
      end,
      ref_resolver: {
        URI('json-schemer://testschema/const-ref') => { 'const' => 'valid-const' }
      }.to_proc,
      regexp_resolver: 'ecma',
      output_format: 'basic',
      resolve_enumerators: true,
      access_mode: 'read'
    )

    schema = {
      'type' => 'object',
      'properties' => {
        'meta-schema' => {
          '$ref' => 'const-ref',
          'const' => 'ignored'
        },
        'custom-format-test' => {
          'format' => 'custom-format'
        },
        'custom-content-encoding-test' => {
          'contentEncoding' => 'custom-content-encoding'
        },
        'custom-media-type-test' => {
          'contentMediaType' => 'custom-media-type'
        },
        'custom-keyword-test' => {
          'custom-keyword' => true
        },
        'custom-default-test' => {
          'default' => 'ignored'
        },
        'ref-test' => {
          '$ref' => 'const-ref'
        },
        'regexp-test' => {
          'pattern' => '^valid-regexp$'
        },
        'access-mode-test-read' => {
          'readOnly' => true
        },
        'access-mode-test-write' => {
          'writeOnly' => true
        }
      }
    }
    schemer = JSONSchemer.schema(schema, configuration: configuration)

    assert_equal(URI('json-schemer://testschema'), schemer.base_uri)
    refute(before_property_validation)
    refute(after_property_validation)

    valid_draft7_schema = { 'meta-schema' => 'valid-const' }
    assert(schemer.valid?(valid_draft7_schema))
    refute(JSONSchemer.schema(schema, configuration: configuration, meta_schema: JSONSchemer.draft201909).valid?(valid_draft7_schema))

    custom_meta_schema = JSONSchemer.schema(
      {
        '$schema' => 'http://example.com/schema',
        'maximum' => 1,
        'exclusiveMaximum' => true
      },
      configuration: JSONSchemer::Configuration.new(vocabulary: { 'json-schemer://draft4' => true }),
      base_uri: URI('http://example.com/schema')
    )
    assert(JSONSchemer.valid_schema?(0, meta_schema: custom_meta_schema))
    refute(JSONSchemer.valid_schema?(1, meta_schema: custom_meta_schema))

    refute(JSONSchemer.schema({ 'format' => 'email' }).valid?('invalid'))
    assert(JSONSchemer.schema({ 'format' => 'email' }, configuration: JSONSchemer::Configuration.new(format: false)).valid?('invalid'))

    assert(schemer.valid?({ 'custom-format-test' => 'valid-format' }))
    refute(schemer.valid?({ 'custom-format-test' => 'invalid' }))

    assert(schemer.valid?({ 'custom-content-encoding-test' => 'valid-content-encoding' }))
    refute(schemer.valid?({ 'custom-content-encoding-test' => 'invalid' }))

    assert(schemer.valid?({ 'custom-media-type-test' => 'valid-media-type' }))
    refute(schemer.valid?({ 'custom-media-type-test' => 'invalid' }))

    assert(schemer.valid?({ 'custom-keyword-test' => 'valid-keyword' }))
    refute(schemer.valid?({ 'custom-keyword-test' => 'invalid' }))

    assert(before_property_validation)
    assert(after_property_validation)

    data = {}
    assert(schemer.valid?(data))
    assert_equal('custom-default', data.fetch('custom-default-test'))

    assert(schemer.valid?({ 'ref-test' => 'valid-const' }))
    refute(schemer.valid?({ 'ref-test' => 'invalid' }))

    assert(schemer.valid?({ 'regexp-test' => 'valid-regexp' }))
    refute(schemer.valid?({ 'regexp-test' => "\nvalid-regexp\n" }))

    assert(schemer.validate({}).fetch('valid'))
    assert_kind_of(Array, schemer.validate('invalid').fetch('errors'))

    assert(schemer.valid?({ 'access-mode-test-read' => '?' }))
    refute(schemer.valid?({ 'access-mode-test-read' => '?' }, access_mode: 'write'))
    refute(schemer.valid?({ 'access-mode-test-write' => '?' }))
    assert(schemer.valid?({ 'access-mode-test-write' => '?' }, access_mode: 'write'))
  end
end
