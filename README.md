# JSONSchemer

JSON Schema validator. Supports drafts 4, 6, 7 and OpenApi 3.0.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'json_schemer'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install json_schemer

## Usage

```ruby
require 'json_schemer'

schema = {
  'type' => 'object',
  'properties' => {
    'abc' => {
      'type' => 'integer',
      'minimum' => 11
    }
  }
}
schemer = JSONSchemer.schema(schema)

# true/false validation

schemer.valid?({ 'abc' => 11 })
# => true

schemer.valid?({ 'abc' => 10 })
# => false

# error validation (`validate` returns an enumerator)

schemer.validate({ 'abc' => 10 }).to_a
# => [{"data"=>10, "schema"=>{"type"=>"integer", "minimum"=>11}, "pointer"=>"#/abc", "type"=>"minimum"}]

# schema files

require 'pathname'

schema = Pathname.new('/path/to/schema.json')
schemer = JSONSchemer.schema(schema)

# schema json string

schema = '{ "type": "integer" }'
schemer = JSONSchemer.schema(schema)
```

## Options

```ruby
JSONSchemer.schema(
  schema,

  # validate `format` (https://tools.ietf.org/html/draft-handrews-json-schema-validation-00#section-7)
  # true/false
  # default: true
  format: true,

  # resolve external references
  # 'net/http'/proc/lambda/respond_to?(:call)
  # 'net/http': proc { |uri| JSON.parse(Net::HTTP.get(uri)) }
  # default: proc { |uri| raise UnknownRef, uri.to_s }
  ref_resolver: 'net/http',

  # Specify which schema to use. Auto-detected via $schema. Defaults to Draft7
  # default: nil
  schema: JSONSchemer::Schema::Draft7
)
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Build Status

[![Build Status](https://travis-ci.org/davishmcclurg/json_schemer.svg?branch=master)](https://travis-ci.org/davishmcclurg/json_schemer)

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/davishmcclurg/json_schemer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
