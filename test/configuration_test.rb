require 'test_helper'

class ConfigurationTest < Minitest::Test
  def run_configuration_test(option, default:, test:, expectation: test)
    if default.nil?
      assert_nil(JSONSchemer.configuration.public_send(option))
    else
      assert_equal(default, JSONSchemer.configuration.public_send(option))
    end

    JSONSchemer.configure { |config| config.public_send("#{option}=", test) }

    assert_equal(expectation, JSONSchemer.configuration.public_send(option))

    # We need to reset the configuration to avoid "polluting" other tests.
    JSONSchemer.configure { |config| config.public_send("#{option}=", default) }
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

  def test_before_property_validation_without_array
    run_configuration_test(
      :before_property_validation,
      default: JSONSchemer::Configuration::Defaults::BEFORE_PROPERTY_VALIDATION,
      test: 'something',
      expectation: ['something']
    )
  end

  def test_after_property_validation
    run_configuration_test(
      :after_property_validation,
      default: JSONSchemer::Configuration::Defaults::AFTER_PROPERTY_VALIDATION,
      test: ['something']
    )
  end

  def test_after_property_validation_without_array
    run_configuration_test(
      :after_property_validation,
      default: JSONSchemer::Configuration::Defaults::AFTER_PROPERTY_VALIDATION,
      test: 'something',
      expectation: ['something']
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
