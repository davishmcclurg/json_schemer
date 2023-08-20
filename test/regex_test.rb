require 'test_helper'

class RegexTest < Minitest::Test
  def test_it_handles_regex_anchors
    schema = JSONSchemer.schema({ 'pattern' => '^foo$' }, :regexp_resolver => 'ecma')
    assert(schema.valid?('foo'))
    refute(schema.valid?(' foo'))
    refute(schema.valid?('foo '))
    refute(schema.valid?("bar\nfoo\nbar"))

    schema = JSONSchemer.schema({ 'pattern' => '^foo$' })
    assert(schema.valid?('foo'))
    refute(schema.valid?(' foo'))
    refute(schema.valid?('foo '))
    assert(schema.valid?("bar\nfoo\nbar"))

    assert_raises(JSONSchemer::InvalidEcmaRegexp) do
      JSONSchemer.schema({ 'pattern' => '\Afoo\z' }, :regexp_resolver => 'ecma').valid?('foo')
    end

    schema = JSONSchemer.schema({ 'pattern' => '\Afoo\z' })
    assert(schema.valid?('foo'))
    refute(schema.valid?(' foo'))
    refute(schema.valid?('foo '))
    refute(schema.valid?("bar\nfoo\nbar"))
  end

  def test_it_handles_regexp_resolver
    new_regexp_class = Class.new do
      def self.counts
        @@counts ||= 0
      end

      def self.counts=(value)
        @@counts = value
      end

      def initialize(pattern)
        @regexp = Regexp.new(pattern)
        self.class.counts += 1
      end

      def match?(string)
        @regexp.match?(string)
      end
    end

    schema = JSONSchemer.schema({ 'pattern' => '^foo$' }, regexp_resolver: -> (pattern) { new_regexp_class.new(pattern) })
    assert(schema.valid?('foo'))
    assert_equal(1, new_regexp_class.counts)
  end

  def test_it_allows_named_regexp_resolvers
    schema = JSONSchemer.schema({ 'pattern' => '^test$' })
    assert(schema.valid?("test"))
    assert(schema.valid?("\ntest\n"))
    schema = JSONSchemer.schema({ 'pattern' => '^test$' }, :regexp_resolver => 'ecma')
    assert(schema.valid?("test"))
    refute(schema.valid?("\ntest\n"))
    schema = JSONSchemer.schema({ 'pattern' => '^test$' }, :regexp_resolver => 'ruby')
    assert(schema.valid?("test"))
    assert(schema.valid?("\ntest\n"))
  end

  def test_it_raises_for_invalid_regexp_resolution
    assert_raises(JSONSchemer::InvalidRegexpResolution) do
      JSONSchemer.schema(
        { 'pattern' => 'whatever' },
        :regexp_resolver => proc { |pattern| nil }
      )
    end
  end

  def test_cached_regexp_resolver
    schema = {
      'properties' => {
        'x' => { 'pattern' => '^1$' },
        'y' => { 'pattern' => '^1$' },
        'z' => { 'pattern' => '^2$' }
      }
    }
    data = { 'x' => '1', 'y' => '1', 'z' => '2' }
    counts = Hash.new(0)
    regexp_resolver = proc do |pattern|
      counts[pattern] += 1
      Regexp.new(pattern)
    end
    assert(JSONSchemer.schema(schema, :regexp_resolver => regexp_resolver).valid?(data))
    assert_equal(2, counts['^1$'])
    assert_equal(1, counts['^2$'])
    counts.clear
    assert(JSONSchemer.schema(schema, :regexp_resolver => JSONSchemer::CachedResolver.new(&regexp_resolver)).valid?(data))
    assert_equal(1, counts['^1$'])
    assert_equal(1, counts['^2$'])
  end

  def test_nul_regex_escape
    schema = JSONSchemer.schema({ 'format' => 'regex' })
    assert(schema.valid?('\0'))
  end
end
