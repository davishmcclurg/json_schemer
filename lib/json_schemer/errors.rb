# Based on code from @robacarp found in issue 48:
# https://github.com/davishmcclurg/json_schemer/issues/48
#
module JSONSchemer
  module Errors
    module_function

    def pretty(error)
      data_path = format_data_pointer error['data_pointer']

      case error['type']
      when 'required'
        keys = error['details']['missing_keys'].join(', ')
        "#{data_path} is missing required keys: #{keys}"
      when 'null',
           'string',
           'boolean',
           'integer',
           'number',
           'array',
           'object'
        "property '#{data_path}' should be of type: #{error['type']}"
      when 'pattern'
        pattern = error['schema']['pattern']
        "property '#{data_path}' does not match pattern: #{pattern}"
      when 'format'
        format = error['schema']['format']
        "property '#{data_path}' does not match format: #{format}"
      when 'const'
        value = error['schema']['const'].dump
        "property '#{data_path}' is not: #{value}"
      when 'enum'
        options = error['schema']['enum']
        "property '#{data_path}' is not one of enum: #{options}"
      else
        "does not validate: error_type=#{error['type']}"
      end
    end

    def format_data_pointer(data_pointer)
      return 'root' if data_pointer.nil? || data_pointer.empty?

      data_pointer
        .sub(%r{^/}, '')   # remove leading /
        .sub('/', '.')     # convert / into .
    end
  end
end
