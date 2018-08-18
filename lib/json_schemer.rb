# frozen_string_literal: true

require 'json_schemer/version'
require 'json_schemer/format'
require 'json_schemer/cached_ref_resolver'
require 'json_schemer/schema/base'
require 'json_schemer/schema/draft4'
require 'json_schemer/schema/draft6'
require 'json_schemer/schema/draft7'

module JSONSchemer
  class UnsupportedMetaSchema < StandardError; end
  class UnknownRef < StandardError; end

  DRAFT_CLASS_BY_META_SCHEMA = {
    'http://json-schema.org/draft-04/schema#' => Schema::Draft4,
    'http://json-schema.org/draft-06/schema#' => Schema::Draft6,
    'http://json-schema.org/draft-07/schema#' => Schema::Draft7
  }.freeze

  DEFAULT_META_SCHEMA = 'http://json-schema.org/draft-07/schema#'

  def self.schema(schema, **options)
    meta_schema = schema.is_a?(Hash) && schema.key?('$schema') ? schema['$schema'] : DEFAULT_META_SCHEMA
    draft_class = DRAFT_CLASS_BY_META_SCHEMA[meta_schema] || raise(UnsupportedMetaSchema, meta_schema)
    draft_class.new(schema, **options)
  end
end
