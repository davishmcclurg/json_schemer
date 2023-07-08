if RUBY_ENGINE == 'ruby'
  require 'simplecov'

  SimpleCov.start do
    enable_coverage :branch
    enable_coverage_for_eval
    minimum_coverage line: 100, branch: 100
  end
end

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "json_schemer"

require "minitest/autorun"

module OutputHelper
  def self.as_json!(output)
    if output.is_a?(Hash)
      output['errors'] = as_json!(output.fetch('errors')) if output.key?('errors')
      output['annotations'] = as_json!(output.fetch('annotations')) if output.key?('annotations')
      output
    elsif output.is_a?(Enumerator)
      output.map { |suboutput| as_json!(suboutput) }
    else
      output
    end
  end
end
