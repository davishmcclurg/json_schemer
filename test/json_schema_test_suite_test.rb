require 'test_helper'

class JSONSchemaTestSuiteTest < Minitest::Test
  INCOMPATIBLE_FILES = if RUBY_ENGINE == 'truffleruby'
    # :nocov:
    Set[
      'JSON-Schema-Test-Suite/tests/draft2020-12/optional/ecmascript-regex.json',
      'JSON-Schema-Test-Suite/tests/draft2019-09/optional/ecmascript-regex.json',
      'JSON-Schema-Test-Suite/tests/draft7/optional/ecmascript-regex.json',
      'JSON-Schema-Test-Suite/tests/draft6/optional/ecmascript-regex.json',
      'JSON-Schema-Test-Suite/tests/draft4/optional/ecmascript-regex.json'
    ]
    # :nocov:
  else
    Set[]
  end

  OUTPUT_DRAFTS = {
    'draft2020-12' => JSONSchemer::DRAFT202012,
    'draft2019-09' => JSONSchemer::DRAFT201909
  }
  DRAFTS = OUTPUT_DRAFTS.merge(
    'draft7' => JSONSchemer::DRAFT7,
    'draft6' => JSONSchemer::DRAFT6,
    'draft4' => JSONSchemer::DRAFT4
  )

  OUTPUT_SCHEMAS = OUTPUT_DRAFTS.each_with_object({}) do |(draft, _meta_schema), out|
    out[draft] = JSON.parse(Pathname.new(__dir__).join('..', 'JSON-Schema-Test-Suite', 'output-tests', draft, 'output-schema.json').read)
  end
  OUTPUT_SCHEMAS_BY_BASE_URI = OUTPUT_SCHEMAS.each_value.each_with_object({}) do |output_schema, out|
    out[URI(output_schema.fetch('$id'))] = output_schema
  end
  OUTPUT_SCHEMERS_BY_DRAFT_AND_OUTPUT_FORMAT = OUTPUT_SCHEMAS.transform_values do |output_schema|
    output_schema = output_schema.dup
    output_schema.delete('anyOf')
    %w[flag basic detailed verbose].each_with_object({}) do |output_format, out|
      out[output_format] = JSONSchemer.schema(output_schema.merge('$ref' => "#/$defs/#{output_format}"), :regexp_resolver => 'ecma')
    end
  end

  REF_RESOLVER = JSONSchemer::CachedResolver.new do |uri|
    if uri.host == 'localhost'
      path = Pathname.new(__dir__).join('..', 'JSON-Schema-Test-Suite', 'remotes', uri.path.gsub(/\A\//, ''))
      JSON.parse(path.read)
    else
      JSON.parse(Net::HTTP.get(uri))
    end
  end

  def test_json_schema_test_suite
    DRAFTS.each do |draft, meta_schema|
      output_schemers = OUTPUT_SCHEMERS_BY_DRAFT_AND_OUTPUT_FORMAT[draft]

      output = Dir["JSON-Schema-Test-Suite/tests/#{draft}/**/*.json"].each_with_object({}) do |file, file_output|
        file_output[file] = JSON.parse(File.read(file)).map do |defn|
          tests, schema = defn.values_at('tests', 'schema')

          schemer = JSONSchemer::Schema.new(
            schema,
            :meta_schema => meta_schema,
            :format => file.start_with?("JSON-Schema-Test-Suite/tests/#{draft}/optional/"),
            :ref_resolver => REF_RESOLVER,
            :regexp_resolver => 'ecma'
          )

          assert(schemer.valid_schema?)
          assert(JSONSchemer.valid_schema?(schema, :meta_schema => meta_schema, :ref_resolver => REF_RESOLVER))

          tests.map do |test|
            data, valid = test.values_at('data', 'valid')

            assert_equal(
              valid,
              schemer.valid?(data),
              JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
            )

            assert_equal(
              valid,
              schemer.validate(data, :output_format => 'basic').fetch('valid'),
              JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
            )

            output_schemers&.each do |output_format, output_schemer|
              output = OutputHelper.as_json!(schemer.validate(data, :output_format => output_format))
              assert(output_schemer.valid?(output))
            end

            schemer.validate(data, :output_format => 'classic').to_a
          rescue
            # :nocov:
            puts JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
            raise
            # :nocov:
          end
        end
      rescue JSON::ParserError => e
        # :nocov:
        raise unless Encoding::CompatibilityError === e.cause && INCOMPATIBLE_FILES.include?(file)
        # :nocov:
      end

      fixture = Pathname.new(__dir__).join('fixtures', "#{draft}.json")
      # :nocov:
      if ENV['WRITE_FIXTURES'] == 'true'
        fixture.write("#{JSON.pretty_generate(output)}\n")
      else
        fixture_json = JSON.parse(fixture.read)
        INCOMPATIBLE_FILES.each { |file| fixture_json.delete(file) }
        assert_equal(output, fixture_json)
      end
      # :nocov:
    end
  end

  def test_json_schema_test_suite_output
    OUTPUT_DRAFTS.each do |draft, _meta_schema|
      Dir["JSON-Schema-Test-Suite/output-tests/#{draft}/content/**/*.json"].each do |file|
        JSON.parse(File.read(file)).each do |defn|
          tests, schema = defn.values_at('tests', 'schema')

          schemer = JSONSchemer.schema(schema, :regexp_resolver => 'ecma')

          tests.each do |test|
            data, output = test.values_at('data', 'output')

            output.each do |output_format, output_schema|
              output_schemer = JSONSchemer.schema(
                output_schema,
                :ref_resolver => OUTPUT_SCHEMAS_BY_BASE_URI.to_proc,
                :regexp_resolver => 'ecma'
              )

              output = OutputHelper.as_json!(schemer.validate(data, :output_format => output_format))

              assert(
                output_schemer.valid?(output),
                JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
              )
            end
          rescue
            # :nocov:
            puts JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
            raise
            # :nocov:
          end
        end
      end
    end
  end

  def test_meta_schemas
    JSONSchemer::META_SCHEMAS_BY_BASE_URI_STR.each do |_base_uri_str, schemer|
      assert(schemer.valid_schema?)
      assert(JSONSchemer.valid_schema?(schemer.value))
    end
  end
end
