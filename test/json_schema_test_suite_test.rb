require 'test_helper'

class JSONSchemaTestSuiteTest < Minitest::Test
  DRAFTS = {
    'draft4' => JSONSchemer::Schema::Draft4,
    'draft6' => JSONSchemer::Schema::Draft6,
    'draft7' => JSONSchemer::Schema::Draft7
  }

  def test_json_schema_test_suite
    ref_resolver = proc do |uri|
      if uri.host == 'localhost'
        path = Pathname.new(__dir__).join('..', 'JSON-Schema-Test-Suite', 'remotes', uri.path.gsub(/\A\//, ''))
        JSON.parse(path.read)
      else
        JSON.parse(Net::HTTP.get(uri))
      end
    end

    DRAFTS.each do |draft, draft_class|
      files = Dir["JSON-Schema-Test-Suite/tests/#{draft}/**/*.json"]
      fixture = Pathname.new(__dir__).join('fixtures', "#{draft}.json")

      output = files.each_with_object({}) do |file, file_output|
        next if file == 'JSON-Schema-Test-Suite/tests/draft7/optional/cross-draft.json'

        definitions = JSON.parse(File.read(file))

        file_output[file] = definitions.map do |defn|
          tests, schema = defn.values_at('tests', 'schema')

          tests.map do |test|
            data, valid = test.values_at('data', 'valid')

            errors = draft_class.new(schema, ref_resolver: ref_resolver).validate(data).to_a

            if valid
              assert_empty(errors, "file: #{file}\nschema: #{JSON.pretty_generate(schema)}\ntest: #{JSON.pretty_generate(test)}")
            else
              refute_empty(errors, "file: #{file}\nschema: #{JSON.pretty_generate(schema)}\ntest: #{JSON.pretty_generate(test)}")
            end

            errors
          end
        end
      end

      if ENV['WRITE_FIXTURES'] == 'true'
        fixture.write("#{JSON.pretty_generate(output)}\n")
      else
        assert_equal(output, JSON.parse(fixture.read))
      end
    end
  end
end
