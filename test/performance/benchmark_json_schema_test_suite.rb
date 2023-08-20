# frozen_string_literal: true
require 'bundler/inline'

require 'benchmark'
require 'json'

gemfile do
  source 'https://rubygems.org'

  gem 'net-ftp' # json-schema
  gem 'webrick' # jschema

  gem 'jschema'
  gem 'json-schema'
  gem 'json_schema'
  gem 'json_validation'
  gem 'rj_schema'

  gem 'json_schemer', :path => '.'
end

$meta_schema = JSONSchemer.draft4
$ref_uris = Dir["JSON-Schema-Test-Suite/remotes/**/*.json"].each_with_object({}) do |file, out|
  uri = URI("http://localhost:1234#{file.delete_prefix('JSON-Schema-Test-Suite/remotes')}")
  out[uri] = JSON.parse(File.read(file))
end
$ref_uris[URI('http://json-schema.org/draft-04/schema')] = JSONSchemer::Draft4::SCHEMA
$ref_resolver = $ref_uris.to_proc

$ref_strs = $ref_uris.transform_keys(&:to_s).slice(
  'http://json-schema.org/draft-04/schema',
  'http://localhost:1234/integer.json',
  'http://localhost:1234/subSchemas.json',
  'http://localhost:1234/baseUriChange/folderInteger.json',
  'http://localhost:1234/baseUriChangeFolder/folderInteger.json',
  'http://localhost:1234/baseUriChangeFolderInSubschema/folderInteger.json',
  'http://localhost:1234/name.json',
  'http://localhost:1234/locationIndependentIdentifierDraft4.json'
)

$draft4 = Dir["JSON-Schema-Test-Suite/tests/draft4/**/*.json"].flat_map do |file|
  JSON.parse(File.read(file)).flat_map do |defn|
    tests, schema = defn.values_at('tests', 'schema')

    tests.map do |test|
      data, valid = test.values_at('data', 'valid')

      [valid, schema, data]
    end
  end
end

JsonSchema.configure do |config|
  config.register_format('unknown', proc { true })
end

$ref_strs.each do |uri, schema|
  JSON::Validator.add_schema(JSON::Schema.new(schema, Addressable::URI.parse(uri)))
end

implementations = {
  # 'jschema' => {
  #   :initialize => proc { |schema| JSchema.build(schema) },
  #   :validate => proc { |initialized, data| initialized.validate(data).none? }
  # },
  'json-schema' => {
    :initialize => proc { |schema| schema },
    :validate => proc { |schema, data| JSON::Validator.fully_validate(schema, data).none? }
  },
  'json_schema' => {
    :initialize => proc { |schema| JsonSchema.parse!(schema) },
    :validate => proc do |initialized, data|
      success, errors = initialized.validate(data)
      (success && errors.none?)
    end
  },
  'json_schemer' => {
    :initialize => proc { |schema| JSONSchemer.schema(schema, :meta_schema => $meta_schema, :ref_resolver => $ref_resolver, :regexp_resolver => 'ecma') },
    :validate => proc { |initialized, data| initialized.validate(data, :output_format => 'basic').fetch('valid') }
  },
  'json_validation' => {
    :initialize => proc { |schema| JsonValidation.build_validator(schema) },
    :validate => proc { |initialized, data| initialized.validate(data) }
  },
  'rj_schema' => {
    :initialize => proc { |schema| RjSchema::Validator.new('/main' => schema, **$ref_strs) },
    :validate => proc { |initialized, data| initialized.validate(:'/main', data).fetch(:machine_errors).none? }
  }
}

$results = {}

Benchmark.bmbm do |x|
  implementations.each do |name, implementation|
    $results[name] = {}

    initialize, validate = implementation.fetch_values(:initialize, :validate)

    initialized = $draft4.map do |valid, schema, data|
      [valid, initialize.call(schema), data]
    end

    {
      :uninitialized => {
        :tests => $draft4,
        :check => proc { |schema, data| validate.call(initialize.call(schema), data) }
      },
      :initialized => {
        :tests => initialized,
        :check => proc { |initialized, data| validate.call(initialized, data) }
      }
    }.each do |type, defn|
      $results[name][type] = { :success => 0, :failure => 0, :error => 0, :errors => Hash.new(0) }

      tests, check = defn.fetch_values(:tests, :check)

      x.report("#{type}: #{name}") do
        tests.each do |valid, *args|
          if valid == check.call(*args)
            $results[name][type][:success] += 1
          else
            $results[name][type][:failure] += 1
          end
        rescue Exception => e
          $results[name][type][:error] += 1
          $results[name][type][:errors][e.class] += 1
        end
      end
    end
  end
end

# puts JSON.pretty_generate($results)
