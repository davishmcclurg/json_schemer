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
require 'json_schemer/format/duration'
require 'json_schemer/format/hostname'
require 'json_schemer/format/json_pointer'
require 'json_schemer/format/uri_template'
require 'json_schemer/format/email'
require 'json_schemer/format'
require 'json_schemer/errors'
require 'json_schemer/cached_resolver'
require 'json_schemer/ecma_regexp'
require 'json_schemer/location'
require 'json_schemer/result'
require 'json_schemer/output'
require 'json_schemer/keyword'
require 'json_schemer/draft202012/meta'
require 'json_schemer/draft202012/vocab/core'
require 'json_schemer/draft202012/vocab/applicator'
require 'json_schemer/draft202012/vocab/unevaluated'
require 'json_schemer/draft202012/vocab/validation'
require 'json_schemer/draft202012/vocab/format_annotation'
require 'json_schemer/draft202012/vocab/format_assertion'
require 'json_schemer/draft202012/vocab/content'
require 'json_schemer/draft202012/vocab'
require 'json_schemer/draft201909/meta'
require 'json_schemer/draft201909/vocab/core'
require 'json_schemer/draft201909/vocab/applicator'
require 'json_schemer/draft201909/vocab'
require 'json_schemer/draft7/meta'
require 'json_schemer/draft7/vocab/validation'
require 'json_schemer/draft7/vocab'
require 'json_schemer/draft6/meta'
require 'json_schemer/draft6/vocab'
require 'json_schemer/draft4/meta'
require 'json_schemer/draft4/vocab/validation'
require 'json_schemer/draft4/vocab'
require 'json_schemer/schema'

module JSONSchemer
  class UnsupportedMetaSchema < StandardError; end
  class UnknownRef < StandardError; end
  class UnknownFormat < StandardError; end
  class UnknownVocabulary < StandardError; end
  class UnknownContentEncoding < StandardError; end
  class UnknownContentMediaType < StandardError; end
  class UnknownOutputFormat < StandardError; end
  class InvalidRefResolution < StandardError; end
  class InvalidRegexpResolution < StandardError; end
  class InvalidFileURI < StandardError; end
  class InvalidSymbolKey < StandardError; end
  class InvalidEcmaRegexp < StandardError; end

  VOCABULARIES = {
    'https://json-schema.org/draft/2020-12/vocab/core' => Draft202012::Vocab::CORE,
    'https://json-schema.org/draft/2020-12/vocab/applicator' => Draft202012::Vocab::APPLICATOR,
    'https://json-schema.org/draft/2020-12/vocab/unevaluated' => Draft202012::Vocab::UNEVALUATED,
    'https://json-schema.org/draft/2020-12/vocab/validation' => Draft202012::Vocab::VALIDATION,
    'https://json-schema.org/draft/2020-12/vocab/format-annotation' => Draft202012::Vocab::FORMAT_ANNOTATION,
    'https://json-schema.org/draft/2020-12/vocab/format-assertion' => Draft202012::Vocab::FORMAT_ASSERTION,
    'https://json-schema.org/draft/2020-12/vocab/content' => Draft202012::Vocab::CONTENT,
    'https://json-schema.org/draft/2020-12/vocab/meta-data' => Draft202012::Vocab::META_DATA,

    'https://json-schema.org/draft/2019-09/vocab/core' => Draft201909::Vocab::CORE,
    'https://json-schema.org/draft/2019-09/vocab/applicator' => Draft201909::Vocab::APPLICATOR,
    'https://json-schema.org/draft/2019-09/vocab/validation' => Draft201909::Vocab::VALIDATION,
    'https://json-schema.org/draft/2019-09/vocab/format' => Draft201909::Vocab::FORMAT,
    'https://json-schema.org/draft/2019-09/vocab/content' => Draft201909::Vocab::CONTENT,
    'https://json-schema.org/draft/2019-09/vocab/meta-data' => Draft201909::Vocab::META_DATA,

    'json-schemer://draft7' => Draft7::Vocab::ALL,
    'json-schemer://draft6' => Draft6::Vocab::ALL,
    'json-schemer://draft4' => Draft4::Vocab::ALL
  }
  VOCABULARY_ORDER = VOCABULARIES.transform_values.with_index { |_vocabulary, index| index }

  DRAFT202012 = Schema.new(
    Draft202012::SCHEMA,
    :base_uri => Draft202012::BASE_URI,
    :ref_resolver => Draft202012::Meta::SCHEMAS.to_proc,
    :regexp_resolver => 'ecma'
  )

  DRAFT201909 = Schema.new(
    Draft201909::SCHEMA,
    :base_uri => Draft201909::BASE_URI,
    :ref_resolver => Draft201909::Meta::SCHEMAS.to_proc,
    :regexp_resolver => 'ecma'
  )

  DRAFT7 = Schema.new(
    Draft7::SCHEMA,
    :vocabulary => { 'json-schemer://draft7' => true },
    :base_uri => Draft7::BASE_URI,
    :regexp_resolver => 'ecma'
  )

  DRAFT6 = Schema.new(
    Draft6::SCHEMA,
    :vocabulary => { 'json-schemer://draft6' => true },
    :base_uri => Draft6::BASE_URI,
    :regexp_resolver => 'ecma'
  )

  DRAFT4 = Schema.new(
    Draft4::SCHEMA,
    :vocabulary => { 'json-schemer://draft4' => true },
    :base_uri => Draft4::BASE_URI,
    :regexp_resolver => 'ecma'
  )

  META_SCHEMAS_BY_BASE_URI_STR = [DRAFT202012, DRAFT201909, DRAFT7, DRAFT6, DRAFT4].each_with_object({}) do |meta_schema, out|
    out[meta_schema.base_uri.to_s] = meta_schema
  end
  META_SCHEMAS_BY_BASE_URI_STR['http://json-schema.org/schema#'] = DRAFT4 # version-less $schema deprecated after Draft 4
  META_SCHEMAS_BY_BASE_URI_STR.freeze

  WINDOWS_URI_PATH_REGEX = /\A\/[a-z]:/i

  FILE_URI_REF_RESOLVER = proc do |uri|
    raise InvalidFileURI, 'must use `file` scheme' unless uri.scheme == 'file'
    raise InvalidFileURI, 'cannot have a host (use `file:///`)' if uri.host && !uri.host.empty?
    path = uri.path
    path = path[1..-1] if path.match?(WINDOWS_URI_PATH_REGEX)
    JSON.parse(File.read(URI::DEFAULT_PARSER.unescape(path)))
  end

  class << self
    def schema(schema, meta_schema: DRAFT202012, **options)
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
      unless meta_schema.is_a?(Schema)
        meta_schema = META_SCHEMAS_BY_BASE_URI_STR[meta_schema] || raise(UnsupportedMetaSchema, meta_schema)
      end
      Schema.new(schema, :meta_schema => meta_schema, **options)
    end

    def valid_schema?(schema, **options)
      schema(schema, **options).valid_schema?
    end

    def validate_schema(schema, **options)
      schema(schema, **options).validate_schema
    end
  end
end
