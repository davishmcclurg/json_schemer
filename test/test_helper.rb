require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  enable_coverage_for_eval
end

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "json_schemer"

require "minitest/autorun"
