# frozen_string_literal: true
module JSONSchemer
  class OpenAPI
    def initialize(document, **options)
      @document = document

      version = document['openapi']
      @document_schema ||= case version
      when /\A3\.1\.\d+\z/
        JSONSchemer.openapi31_document
      else
        raise UnsupportedOpenAPIVersion, version
      end

      json_schema_dialect = document.fetch('jsonSchemaDialect') { OpenAPI31::BASE_URI.to_s }
      meta_schema = META_SCHEMAS_BY_BASE_URI_STR[json_schema_dialect] || raise(UnsupportedMetaSchema, json_schema_dialect)

      @schema = JSONSchemer.schema(@document, :meta_schema => meta_schema, **options)
    end

    def valid?
      @document_schema.valid?(@document)
    end

    def validate(**options)
      @document_schema.validate(@document, **options)
    end

    def ref(value)
      @schema.resolve_ref(URI.join(@schema.base_uri, value))
    end

    def schema(name)
      ref("#/components/schemas/#{name}")
    end
  end
end
