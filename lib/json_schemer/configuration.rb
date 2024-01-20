# frozen_string_literal: true

module JSONSchemer
  class Configuration
    module Defaults
      BASE_URI = URI('json-schemer://schema').freeze
      FORMATS = {}.freeze
      CONTENT_ENCODINGS = {}.freeze
      CONTENT_MEDIA_TYPES = {}.freeze
      CUSTOM_KEYWORDS = {}.freeze
      BEFORE_PROPERTY_VALIDATION = [].freeze
      AFTER_PROPERTY_VALIDATION = [].freeze
      INSERT_PROPERTY_DEFAULTS = false
      PROPERTY_RESOLVER = proc do |instance, property, results_with_tree_validity|
        unless results_with_tree_validity.size == 1
          results_with_tree_validity = results_with_tree_validity.select(&:last)
        end
        annotations = results_with_tree_validity.to_set { |result, _tree_valid| result.annotation }

        if annotations.size == 1
          instance[property] = annotations.first.clone
          true
        else
          false
        end
      end
      ORIGINAL_REF_RESOLVER = proc { |uri| raise UnknownRef, uri.to_s }
      ORIGINAL_REGEXP_RESOLVER = 'ruby'
      OUTPUT_FORMAT = 'classic'
      RESOLVE_ENUMERATORS = false
      ACCESS_MODE = nil
    end

    attr_accessor(
      :base_uri,
      :formats,
      :content_encodings,
      :content_media_types,
      :custom_keywords,
      :insert_property_defaults,
      :property_default_resolver,
      :original_ref_resolver,
      :resolve_enumerators
      )

    attr_reader(
      :before_property_validation,
      :after_property_validation,
      :original_regexp_resolver,
      :output_format,
      :access_mode
    )

    def initialize
      @base_uri = Defaults::BASE_URI
      @formats = Defaults::FORMATS
      @content_encodings = Defaults::CONTENT_ENCODINGS
      @content_media_types = Defaults::CONTENT_MEDIA_TYPES
      @custom_keywords = Defaults::CUSTOM_KEYWORDS
      @before_property_validation = Defaults::BEFORE_PROPERTY_VALIDATION
      @after_property_validation = Defaults::AFTER_PROPERTY_VALIDATION
      @insert_property_defaults = Defaults::INSERT_PROPERTY_DEFAULTS
      @property_default_resolver = Defaults::PROPERTY_RESOLVER
      @original_ref_resolver = Defaults::ORIGINAL_REF_RESOLVER
      @original_regexp_resolver = Defaults::ORIGINAL_REGEXP_RESOLVER
      @output_format = Defaults::OUTPUT_FORMAT
      @resolve_enumerators = Defaults::RESOLVE_ENUMERATORS
      @access_mode = Defaults::ACCESS_MODE
    end

    def before_property_validation=(validations)
      @before_property_validation = Array(validations)
    end

    def after_property_validation=(validations)
      @after_property_validation = Array(validations)
    end

    def original_regexp_resolver=(resolver)
      if resolver.is_a?(String) && !%w[ruby ecma].include?(resolver)
        raise UnknownRegexpResolver
      end

      @original_regexp_resolver = resolver
    end

    def output_format=(format)
      unless %[classic flag basic detailed verbose].include?(format)
        raise UnknownOutputFormat
      end

      @output_format = format
    end

    def access_mode=(mode)
      if mode.is_a?(String) && !%w[read write].include?(mode)
        raise UnknownAccessMode
      end

      @access_mode = mode
    end
  end
end
