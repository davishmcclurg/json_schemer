# frozen_string_literal: true

module JSONSchemer
  class Configuration
    module Defaults
      BASE_URI = URI('json-schemer://schema').freeze
      FORMATS = {}.freeze
      CONTENT_ENCODINGS = {}.freeze
      CONTENT_MEDIA_TYPES = {}.freeze
      KEYWORDS = {}.freeze
      BEFORE_PROPERTY_VALIDATION = [].freeze
      AFTER_PROPERTY_VALIDATION = [].freeze
      INSERT_PROPERTY_DEFAULTS = false
      PROPERTY_DEFAULT_RESOLVER = nil
      REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
      REGEXP_RESOLVER = 'ruby'
      OUTPUT_FORMAT = 'classic'
      RESOLVE_ENUMERATORS = false
      ACCESS_MODE = nil
    end

    attr_accessor(
      :base_uri,
      :formats,
      :content_encodings,
      :content_media_types,
      :keywords,
      :before_property_validation,
      :after_property_validation,
      :insert_property_defaults,
      :property_default_resolver,
      :ref_resolver,
      :regexp_resolver,
      :output_format,
      :resolve_enumerators,
      :access_mode
      )

    def initialize
      @base_uri = Defaults::BASE_URI
      @formats = Defaults::FORMATS
      @content_encodings = Defaults::CONTENT_ENCODINGS
      @content_media_types = Defaults::CONTENT_MEDIA_TYPES
      @keywords = Defaults::KEYWORDS
      @before_property_validation = Defaults::BEFORE_PROPERTY_VALIDATION
      @after_property_validation = Defaults::AFTER_PROPERTY_VALIDATION
      @insert_property_defaults = Defaults::INSERT_PROPERTY_DEFAULTS
      @property_default_resolver = Defaults::PROPERTY_DEFAULT_RESOLVER
      @ref_resolver = Defaults::REF_RESOLVER
      @regexp_resolver = Defaults::REGEXP_RESOLVER
      @output_format = Defaults::OUTPUT_FORMAT
      @resolve_enumerators = Defaults::RESOLVE_ENUMERATORS
      @access_mode = Defaults::ACCESS_MODE
    end
  end
end
