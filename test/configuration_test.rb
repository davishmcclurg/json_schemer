require 'test_helper'

class ConfigurationTest < Minitest::Test
  def run_configuration_test(option, default: (skip_default = true), test:)
    original = JSONSchemer.configuration.public_send(option)

    if default.nil?
      assert_nil(original)
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
      default: JSONSchemer::Configuration::Defaults::BASE_URI,
      test: URI('some-other://schema')
    )
  end

  def test_meta_schema
    run_configuration_test(
      :meta_schema,
      default: JSONSchemer::Configuration::Defaults::META_SCHEMA,
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
      default: JSONSchemer::Configuration::Defaults::VOCABULARY,
      test: { 'json-schemer://draft4' => true }
    )
  end

  def test_format
    run_configuration_test(
      :format,
      default: JSONSchemer::Configuration::Defaults::FORMAT,
      test: false
    )
  end

  def test_formats
    run_configuration_test(
      :formats,
      default: JSONSchemer::Configuration::Defaults::FORMATS,
      test: {
        'some-format' => lambda { |instance, _format| true }
      }
    )
  end

  def test_content_encodings
    run_configuration_test(
      :content_encodings,
      default: JSONSchemer::Configuration::Defaults::CONTENT_ENCODINGS,
      test: {
        'lowercase' => lambda { |instance| [true, instance&.downcase] }
      }
    )
  end

  def test_content_media_types
    run_configuration_test(
      :content_media_types,
      default: JSONSchemer::Configuration::Defaults::CONTENT_MEDIA_TYPES,
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
      default: JSONSchemer::Configuration::Defaults::KEYWORDS,
      test: {
        'even' => lambda { |data, curr_schema, _pointer| curr_schema.fetch('even') == data.to_i.even? }
      }
    )
  end

  def test_before_property_validation
    run_configuration_test(
      :before_property_validation,
      default: JSONSchemer::Configuration::Defaults::BEFORE_PROPERTY_VALIDATION,
      test: ['something']
    )
  end

  def test_after_property_validation
    run_configuration_test(
      :after_property_validation,
      default: JSONSchemer::Configuration::Defaults::AFTER_PROPERTY_VALIDATION,
      test: ['something']
    )
  end

  def test_insert_property_defaults
    run_configuration_test(
      :insert_property_defaults,
      default: JSONSchemer::Configuration::Defaults::INSERT_PROPERTY_DEFAULTS,
      test: true
    )
  end

  def test_property_default_resolver
    run_configuration_test(
      :property_default_resolver,
      default: JSONSchemer::Configuration::Defaults::PROPERTY_DEFAULT_RESOLVER,
      test: lambda { |instance, property, results_with_tree_validity| true }
    )
  end

  def test_ref_resolver
    run_configuration_test(
      :ref_resolver,
      default: JSONSchemer::Configuration::Defaults::REF_RESOLVER,
      test: lambda { |uri| { 'type' => 'string' } }
    )
  end

  def test_regexp_resolver
    run_configuration_test(
      :regexp_resolver,
      default: JSONSchemer::Configuration::Defaults::REGEXP_RESOLVER,
      test: 'ecma'
    )
  end

  def test_output_format
    run_configuration_test(
      :output_format,
      default: JSONSchemer::Configuration::Defaults::OUTPUT_FORMAT,
      test: 'basic'
    )
  end

  def test_resolve_enumerators
    run_configuration_test(
      :resolve_enumerators,
      default: JSONSchemer::Configuration::Defaults::RESOLVE_ENUMERATORS,
      test: true
    )
  end

  def test_access_mode
    run_configuration_test(
      :access_mode,
      default: JSONSchemer::Configuration::Defaults::ACCESS_MODE,
      test: "write"
    )
  end
end
