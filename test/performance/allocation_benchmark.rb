# frozen_string_literal: true

$LOAD_PATH.unshift(ENV.fetch('LIB_PATH')) if ENV.key?('LIB_PATH')

require 'json_schemer'
require 'memory_profiler'

ITERATIONS = Integer(ENV.fetch('ITERATIONS', '1000'))
BENCH_LABEL = ENV.fetch('BENCH_LABEL', 'current')

SCENARIOS = {
  'object_string_keys' => [
    {
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
    },
    {
      'id' => 1,
      'name' => 'example',
      'tags' => Array.new(20) { |index| "tag-#{index}" },
      'nested' => { 'count' => 20, 'enabled' => true }
    }
  ],
  'array_items' => [
    {
      'type' => 'array',
      'items' => {
        'type' => 'object',
        'properties' => {
          'index' => { 'type' => 'integer' },
          'label' => { 'type' => 'string' }
        },
        'required' => ['index', 'label']
      }
    },
    Array.new(50) { |index| { 'index' => index, 'label' => "item-#{index}" } }
  ],
  'additional_properties' => [
    {
      'type' => 'object',
      'properties' => {
        'known' => { 'type' => 'string' }
      },
      'additionalProperties' => { 'type' => 'integer' }
    },
    { 'known' => 'ok' }.merge(50.times.to_h { |index| ["extra_#{index}", index] })
  ]
}.freeze

FORMATS = ['valid?', 'flag', 'basic'].freeze
ALL_MODES = {
  'default' => {},
  'stringified_keys' => { :stringified_keys => true }
}.freeze
MODES = ENV.fetch('BENCH_MODES', ALL_MODES.keys.join(',')).split(',').to_h do |mode|
  [mode, ALL_MODES.fetch(mode)]
end.freeze

def profile
  GC.start
  GC.disable
  reporter = MemoryProfiler::Reporter.new
  reporter.start
  begin
    ITERATIONS.times { yield }
  ensure
    reporter.stop
    GC.enable
  end
  reporter.report_results
end

def measure_schema_construction(schema_value, options)
  100.times { JSONSchemer.schema(schema_value, **options) }
  profile { JSONSchemer.schema(schema_value, **options) }
end

def measure_validation(schema, instance, output_format)
  validate = output_format == 'valid?' ? :valid? : :validate
  100.times do
    validate == :valid? ? schema.valid?(instance) : schema.validate(instance, :output_format => output_format)
  end

  profile do
    validate == :valid? ? schema.valid?(instance) : schema.validate(instance, :output_format => output_format)
  end
end

def print_report(operation, scenario, mode, format, report)
  total_allocated = report.total_allocated
  total_allocated_memsize = report.total_allocated_memsize
  puts [
    BENCH_LABEL,
    operation,
    scenario,
    mode,
    format,
    total_allocated,
    total_allocated_memsize,
    (total_allocated.to_f / ITERATIONS).round(2),
    (total_allocated_memsize.to_f / ITERATIONS).round(2)
  ].join(',')
end

puts "iterations=#{ITERATIONS}"
puts 'setup,operation,scenario,mode,format,total_allocated,total_allocated_memsize,allocations_per_operation,bytes_per_operation'

SCENARIOS.each do |name, (schema_value, instance)|
  MODES.each do |mode, options|
    report = measure_schema_construction(schema_value, options)
    print_report('schema_construction', name, mode, '-', report)

    schema = JSONSchemer.schema(schema_value, **options)
    FORMATS.each do |output_format|
      report = measure_validation(schema, instance, output_format)
      print_report('validation', name, mode, output_format, report)
    end
  end
end
