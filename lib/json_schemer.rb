# frozen_string_literal: true
require 'base64'
require 'bigdecimal'
require 'ipaddr'
require 'json'
require 'net/http'
require 'pathname'
require 'set'
require 'time'
require 'uri'

require 'hana'
require 'regexp_parser'
require 'simpleidn'

require 'json_schemer/version'
require 'json_schemer/format/hostname'
require 'json_schemer/format/uri_template'
require 'json_schemer/format/email'
require 'json_schemer/format'
require 'json_schemer/errors'
require 'json_schemer/cached_resolver'
require 'json_schemer/ecma_regexp'
require 'json_schemer/schema/base'
require 'json_schemer/schema/draft4'
require 'json_schemer/schema/draft6'
require 'json_schemer/schema/draft7'

module JSONSchemer
  class UnsupportedMetaSchema < StandardError; end
  class UnknownRef < StandardError; end
  class UnknownFormat < StandardError; end
  class InvalidRefResolution < StandardError; end
  class InvalidRegexpResolution < StandardError; end
  class InvalidFileURI < StandardError; end
  class InvalidSymbolKey < StandardError; end
  class InvalidEcmaRegexp < StandardError; end

  DEFAULT_SCHEMA_CLASS = Schema::Draft7
  SCHEMA_CLASS_BY_META_SCHEMA = {
    'http://json-schema.org/schema#' => Schema::Draft4, # Version-less $schema deprecated after Draft 4
    'http://json-schema.org/draft-04/schema#' => Schema::Draft4,
    'http://json-schema.org/draft-06/schema#' => Schema::Draft6,
    'http://json-schema.org/draft-07/schema#' => Schema::Draft7
  }.freeze

  WINDOWS_URI_PATH_REGEX = /\A\/[a-z]:/i

  FILE_URI_REF_RESOLVER = proc do |uri|
    raise InvalidFileURI, 'must use `file` scheme' unless uri.scheme == 'file'
    raise InvalidFileURI, 'cannot have a host (use `file:///`)' if uri.host && !uri.host.empty?
    path = uri.path
    path = path[1..-1] if path.match?(WINDOWS_URI_PATH_REGEX)
    JSON.parse(File.read(URI::DEFAULT_PARSER.unescape(path)))
  end

  class << self
    def schema(schema, default_schema_class: DEFAULT_SCHEMA_CLASS, **options)
      case schema
      when String
        schema = JSON.parse(schema)
      when Pathname
        base_uri = URI.parse(File.join('file:', URI::DEFAULT_PARSER.escape(schema.realpath.to_s)))
        options[:base_uri] = base_uri
        schema = if options.key?(:ref_resolver)
          FILE_URI_REF_RESOLVER.call(base_uri)
        else
          ref_resolver = CachedResolver.new(&FILE_URI_REF_RESOLVER)
          options[:ref_resolver] = ref_resolver
          ref_resolver.call(base_uri)
        end
      end

      schema_class = if schema.is_a?(Hash) && schema.key?('$schema')
        meta_schema = schema.fetch('$schema')
        SCHEMA_CLASS_BY_META_SCHEMA[meta_schema] || raise(UnsupportedMetaSchema, meta_schema)
      else
        default_schema_class
      end

      schema_class.new(schema, **options)
    end

    def valid_schema?(schema, default_schema_class: DEFAULT_SCHEMA_CLASS)
      schema(schema, default_schema_class: default_schema_class).valid_schema?
    end

    def validate_schema(schema, default_schema_class: DEFAULT_SCHEMA_CLASS)
      schema(schema, default_schema_class: default_schema_class).validate_schema
    end
  end
end
