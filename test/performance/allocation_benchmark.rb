# frozen_string_literal: true

require 'json_schemer'
require 'memory_profiler'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', '1000'))

SCHEMAS = {
  'object_string_keys' => [
    JSONSchemer.schema({
      'type' => 'object',
      'properties' => {
        'id' => { 'type' => 'integer' },
        'name' => { 'type' => 'string' },
        'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'nested' => {
          'type' => 'object',
          'properties' => {
            'count' => { 'type' => 'integer' },
            'enabled' => { 'type' => 'boolean' }
          },
          'required' => ['count', 'enabled']
        }
      },
      'required' => ['id', 'name', 'tags', 'nested']
    }),
    {
      'id' => 1,
      'name' => 'example',
      'tags' => Array.new(20) { |index| "tag-#{index}" },
      'nested' => { 'count' => 20, 'enabled' => true }
    }
  ],
  'object_symbol_keys' => [
    JSONSchemer.schema({
      'type' => 'object',
      'properties' => {
        'id' => { 'type' => 'integer' },
        'name' => { 'type' => 'string' },
        'tags' => { 'type' => 'array', 'items' => { 'type' => 'string' } },
        'nested' => {
          'type' => 'object',
          'properties' => {
            'count' => { 'type' => 'integer' },
            'enabled' => { 'type' => 'boolean' }
          },
          'required' => ['count', 'enabled']
        }
      },
      'required' => ['id', 'name', 'tags', 'nested']
    }),
    {
      :id => 1,
      :name => 'example',
      :tags => Array.new(20) { |index| "tag-#{index}" },
      :nested => { :count => 20, :enabled => true }
    }
  ],
  'array_items' => [
    JSONSchemer.schema({
      'type' => 'array',
      'items' => {
        'type' => 'object',
        'properties' => {
          'index' => { 'type' => 'integer' },
          'label' => { 'type' => 'string' }
        },
        'required' => ['index', 'label']
      }
    }),
    Array.new(50) { |index| { 'index' => index, 'label' => "item-#{index}" } }
  ],
  'additional_properties' => [
    JSONSchemer.schema({
      'type' => 'object',
      'properties' => {
        'known' => { 'type' => 'string' }
      },
      'additionalProperties' => { 'type' => 'integer' }
    }),
    { 'known' => 'ok' }.merge(50.times.to_h { |index| ["extra_#{index}", index] })
  ]
}.freeze

FORMATS = ['valid?', 'flag', 'basic'].freeze
MODES = {
  'default' => {},
  'stringified_keys' => { :stringified_keys => true }
}.freeze

def measure(schema, instance, output_format, options)
  validate = output_format == 'valid?' ? :valid? : :validate
  100.times do
    validate == :valid? ? schema.valid?(instance, **options) : schema.validate(instance, :output_format => output_format, **options)
  end

  reporter = MemoryProfiler::Reporter.new
  reporter.start
  gc_count = GC.count
  begin
    ITERATIONS.times do
      validate == :valid? ? schema.valid?(instance, **options) : schema.validate(instance, :output_format => output_format, **options)
    end
    raise "GC ran during benchmark" unless GC.count == gc_count
  ensure
    reporter.stop
  end
  reporter.report_results
ensure
  GC.enable
end

puts "iterations=#{ITERATIONS}"
puts "scenario,mode,format,total_allocated,total_allocated_memsize,allocations_per_validation,bytes_per_validation,gc_runs"

SCHEMAS.each do |name, (schema, instance)|
  FORMATS.each do |output_format|
    MODES.each do |mode, options|
      next if mode == 'stringified_keys' && name == 'object_symbol_keys'
      report = measure(schema, instance, output_format, options)
      total_allocated = report.total_allocated
      total_allocated_memsize = report.total_allocated_memsize
      puts "#{name},#{mode},#{output_format},#{total_allocated},#{total_allocated_memsize},#{(total_allocated.to_f / ITERATIONS).round(2)},#{(total_allocated_memsize.to_f / ITERATIONS).round(2)},0"
    end
  end
end
