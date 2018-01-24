# JSONSchemer

JSON Schema draft-07 validator

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
schemer = JSONSchemer::Schema.new(schema)

# true/false validation

schemer.valid?({ 'abc' => 11 })
# => true

schemer.valid?({ 'abc' => 10 })
# => false

# error validation (`validate` returns an enumerator)

schemer.validate({ 'abc' => 10 }).to_a
# => [{"data"=>10, "schema"=>{"type"=>"integer", "minimum"=>11}, "pointer"=>"#/abc", "type"=>"minimum"}]
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/davishmcclurg/json_schemer.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
