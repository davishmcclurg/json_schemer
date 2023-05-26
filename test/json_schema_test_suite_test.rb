require 'test_helper'

class JSONSchemaTestSuiteTest < Minitest::Test
  def test_json_schema_test_suite
    ref_resolver = proc do |uri|
      if uri.host == 'localhost'
        path = Pathname.new(__dir__).join('..', 'JSON-Schema-Test-Suite', 'remotes', uri.path.gsub(/\A\//, ''))
        JSON.parse(path.read)
      else
        JSON.parse(Net::HTTP.get(uri))
      end
    end

    JSONSchemer::SCHEMA_CLASS_BY_META_SCHEMA.values.uniq.each do |schema_class|
      files = Dir["JSON-Schema-Test-Suite/tests/#{schema_class.draft_name}/**/*.json"]
      fixture = Pathname.new(__dir__).join('fixtures', "#{schema_class.draft_name}.json")

      assert(JSONSchemer.valid_schema?(schema_class.meta_schema))

      output = files.each_with_object({}) do |file, file_output|
        next if file == 'JSON-Schema-Test-Suite/tests/draft7/optional/cross-draft.json'

        definitions = JSON.parse(File.read(file))

        file_output[file] = definitions.map do |defn|
          tests, schema = defn.values_at('tests', 'schema')

          schemer = schema_class.new(schema, ref_resolver: ref_resolver, regexp_resolver: 'ecma')
          assert(schemer.valid_schema?)
          assert(JSONSchemer.valid_schema?(schema, default_schema_class: schema_class))

          tests.map do |test|
            data, valid = test.values_at('data', 'valid')

            errors = schemer.validate(data).to_a

            if valid
              assert_empty(errors, "file: #{file}\nschema: #{JSON.pretty_generate(schema)}\ntest: #{JSON.pretty_generate(test)}")
            else
              refute_empty(errors, "file: #{file}\nschema: #{JSON.pretty_generate(schema)}\ntest: #{JSON.pretty_generate(test)}")
            end

            errors
          end
        end
      end

      # :nocov:
      if ENV['WRITE_FIXTURES'] == 'true'
        fixture.write("#{JSON.pretty_generate(output)}\n")
      else
        assert_equal(output, JSON.parse(fixture.read))
      end
      # :nocov:
    end
  end
end
