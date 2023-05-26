require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  enable_coverage_for_eval
  minimum_coverage line: 100, branch: 100
end

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "json_schemer"

require "minitest/autorun"
