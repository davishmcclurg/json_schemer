# frozen_string_literal: true
require 'bundler/inline'

gemfile do
  source 'https://rubygems.org'
  gem 'json_schemer', :path => '.'
  gem 'ruby-prof'
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
  out[draft] = JSON.parse(Pathname.new(__dir__).join('..', '..', 'JSON-Schema-Test-Suite', 'output-tests', draft, 'output-schema.json').read)
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
    path = Pathname.new(__dir__).join('..', '..', 'JSON-Schema-Test-Suite', 'remotes', uri.path.gsub(/\A\//, ''))
    JSON.parse(path.read)
  else
    JSON.parse(Net::HTTP.get(uri))
  end
end

profile = RubyProf::Profile.profile(:track_allocations => true) do
  DRAFTS.each do |draft, meta_schema|
    output_schemers = OUTPUT_SCHEMERS_BY_DRAFT_AND_OUTPUT_FORMAT[draft]

    Dir["JSON-Schema-Test-Suite/tests/#{draft}/**/*.json"].each do |file|
      JSON.parse(File.read(file)).each do |defn|
        tests, schema = defn.values_at('tests', 'schema')

        schemer = JSONSchemer.schema(
          schema,
          :meta_schema => meta_schema,
          :format => file.start_with?("JSON-Schema-Test-Suite/tests/#{draft}/optional/"),
          :ref_resolver => REF_RESOLVER,
          :regexp_resolver => 'ecma'
        )

        raise unless schemer.valid_schema?
        raise unless JSONSchemer.valid_schema?(schema, :meta_schema => meta_schema, :ref_resolver => REF_RESOLVER)

        tests.each do |test|
          data, valid = test.values_at('data', 'valid')

          raise unless schemer.validate(data, :output_format => 'basic').fetch('valid') == valid

          output_schemers&.each do |output_format, output_schemer|
            raise unless output_schemer.valid?(schemer.validate(data, :output_format => output_format))
          end
        rescue
          puts JSON.pretty_generate('file' => file, 'description' => defn.fetch('description'), 'schema' => schema, 'test' => test)
          raise
        end
      end
    end
  end
end

printer = RubyProf::MultiPrinter.new(profile)
printer.print(:path => ".", :profile => 'profile', :min_percent => 1, :sort_method => :self_time)
