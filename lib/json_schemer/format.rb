# frozen_string_literal: true
module JSONSchemer
  module Format
    # this is no good
    EMAIL_REGEX = /\A[^@\s]+@([\p{L}\d-]+\.)+[\p{L}\d\-]{2,}\z/i.freeze
    LABEL_REGEX_STRING = '\p{L}([\p{L}\p{N}\-]*[\p{L}\p{N}])?'
    HOSTNAME_REGEX = /\A(#{LABEL_REGEX_STRING}\.)*#{LABEL_REGEX_STRING}\z/i.freeze
    JSON_POINTER_REGEX_STRING = '(\/([^~\/]|~[01])*)*'
    JSON_POINTER_REGEX = /\A#{JSON_POINTER_REGEX_STRING}\z/.freeze
    RELATIVE_JSON_POINTER_REGEX = /\A(0|[1-9]\d*)(#|#{JSON_POINTER_REGEX_STRING})?\z/.freeze
    DATE_TIME_OFFSET_REGEX = /(Z|[\+\-]([01][0-9]|2[0-3]):[0-5][0-9])\z/i.freeze

    # https://github.com/ruby-rdf/rdf

    # IRI components
    UCSCHAR = Regexp.compile(<<-EOS.gsub(/\s+/, ''))
      [\\u00A0-\\uD7FF]|[\\uF900-\\uFDCF]|[\\uFDF0-\\uFFEF]|
      [\\u{10000}-\\u{1FFFD}]|[\\u{20000}-\\u{2FFFD}]|[\\u{30000}-\\u{3FFFD}]|
      [\\u{40000}-\\u{4FFFD}]|[\\u{50000}-\\u{5FFFD}]|[\\u{60000}-\\u{6FFFD}]|
      [\\u{70000}-\\u{7FFFD}]|[\\u{80000}-\\u{8FFFD}]|[\\u{90000}-\\u{9FFFD}]|
      [\\u{A0000}-\\u{AFFFD}]|[\\u{B0000}-\\u{BFFFD}]|[\\u{C0000}-\\u{CFFFD}]|
      [\\u{D0000}-\\u{DFFFD}]|[\\u{E1000}-\\u{EFFFD}]
    EOS
    IPRIVATE = Regexp.compile("[\\uE000-\\uF8FF]|[\\u{F0000}-\\u{FFFFD}]|[\\u100000-\\u10FFFD]").freeze
    SCHEME = Regexp.compile("[A-Za-z](?:[A-Za-z0-9+-\.])*").freeze
    PORT = Regexp.compile("[0-9]*").freeze
    IP_LITERAL = Regexp.compile("\\[[0-9A-Fa-f:\\.]*\\]").freeze  # Simplified, no IPvFuture
    PCT_ENCODED = Regexp.compile("%[0-9A-Fa-f][0-9A-Fa-f]").freeze
    GEN_DELIMS = Regexp.compile("[:/\\?\\#\\[\\]@]").freeze
    SUB_DELIMS = Regexp.compile("[!\\$&'\\(\\)\\*\\+,;=]").freeze
    RESERVED = Regexp.compile("(?:#{GEN_DELIMS}|#{SUB_DELIMS})").freeze
    UNRESERVED = Regexp.compile("[A-Za-z0-9\._~-]").freeze

    IUNRESERVED = Regexp.compile("[A-Za-z0-9\._~-]|#{UCSCHAR}").freeze

    IPCHAR = Regexp.compile("(?:#{IUNRESERVED}|#{PCT_ENCODED}|#{SUB_DELIMS}|:|@)").freeze

    IQUERY = Regexp.compile("(?:#{IPCHAR}|#{IPRIVATE}|/|\\?)*").freeze

    IFRAGMENT = Regexp.compile("(?:#{IPCHAR}|/|\\?)*").freeze.freeze

    ISEGMENT = Regexp.compile("(?:#{IPCHAR})*").freeze
    ISEGMENT_NZ = Regexp.compile("(?:#{IPCHAR})+").freeze
    ISEGMENT_NZ_NC = Regexp.compile("(?:(?:#{IUNRESERVED})|(?:#{PCT_ENCODED})|(?:#{SUB_DELIMS})|@)+").freeze

    IPATH_ABEMPTY = Regexp.compile("(?:/#{ISEGMENT})*").freeze
    IPATH_ABSOLUTE = Regexp.compile("/(?:(?:#{ISEGMENT_NZ})(/#{ISEGMENT})*)?").freeze
    IPATH_NOSCHEME = Regexp.compile("(?:#{ISEGMENT_NZ_NC})(?:/#{ISEGMENT})*").freeze
    IPATH_ROOTLESS = Regexp.compile("(?:#{ISEGMENT_NZ})(?:/#{ISEGMENT})*").freeze
    IPATH_EMPTY = Regexp.compile("").freeze

    IREG_NAME   = Regexp.compile("(?:(?:#{IUNRESERVED})|(?:#{PCT_ENCODED})|(?:#{SUB_DELIMS}))*").freeze
    IHOST = Regexp.compile("(?:#{IP_LITERAL})|(?:#{IREG_NAME})").freeze
    IUSERINFO = Regexp.compile("(?:(?:#{IUNRESERVED})|(?:#{PCT_ENCODED})|(?:#{SUB_DELIMS})|:)*").freeze
    IAUTHORITY = Regexp.compile("(?:#{IUSERINFO}@)?#{IHOST}(?::#{PORT})?").freeze

    IRELATIVE_PART = Regexp.compile("(?:(?://#{IAUTHORITY}(?:#{IPATH_ABEMPTY}))|(?:#{IPATH_ABSOLUTE})|(?:#{IPATH_NOSCHEME})|(?:#{IPATH_EMPTY}))").freeze
    IRELATIVE_REF = Regexp.compile("^#{IRELATIVE_PART}(?:\\?#{IQUERY})?(?:\\##{IFRAGMENT})?$").freeze

    IHIER_PART = Regexp.compile("(?:(?://#{IAUTHORITY}#{IPATH_ABEMPTY})|(?:#{IPATH_ABSOLUTE})|(?:#{IPATH_ROOTLESS})|(?:#{IPATH_EMPTY}))").freeze
    IRI = Regexp.compile("^#{SCHEME}:(?:#{IHIER_PART})(?:\\?#{IQUERY})?(?:\\##{IFRAGMENT})?$").freeze

    def valid_spec_format?(data, format)
      case format
      when 'date-time'
        valid_date_time?(data)
      when 'date'
        valid_date_time?("#{data}T04:05:06.123456789+07:00")
      when 'time'
        valid_date_time?("2001-02-03T#{data}")
      when 'email'
        data.ascii_only? && valid_email?(data)
      when 'idn-email'
        valid_email?(data)
      when 'hostname'
        data.ascii_only? && valid_hostname?(data)
      when 'idn-hostname'
        valid_hostname?(data)
      when 'ipv4'
        valid_ip?(data, :v4)
      when 'ipv6'
        valid_ip?(data, :v6)
      when 'uri'
        data.ascii_only? && valid_iri?(data)
      when 'uri-reference'
        data.ascii_only? && (valid_iri?(data) || valid_iri_reference?(data))
      when 'iri'
        valid_iri?(data)
      when 'iri-reference'
        valid_iri?(data) || valid_iri_reference?(data)
      when 'uri-template'
        valid_uri_template?(data)
      when 'json-pointer'
        valid_json_pointer?(data)
      when 'relative-json-pointer'
        valid_relative_json_pointer?(data)
      when 'regex'
        EcmaReValidator.valid?(data)
      end
    end

    def valid_json?(data)
      JSON.parse(data)
      true
    rescue JSON::ParserError
      false
    end

    def valid_date_time?(data)
      DateTime.rfc3339(data)
      DATE_TIME_OFFSET_REGEX.match?(data)
    rescue ArgumentError => e
      raise e unless e.message == 'invalid date'
      false
    end

    def valid_email?(data)
      EMAIL_REGEX.match?(data)
    end

    def valid_hostname?(data)
      HOSTNAME_REGEX.match?(data) && data.split('.').all? { |label| label.size <= 63 }
    end

    def valid_ip?(data, type)
      ip_address = IPAddr.new(data)
      type == :v4 ? ip_address.ipv4? : ip_address.ipv6?
    rescue IPAddr::InvalidAddressError
      false
    end

    def valid_iri?(data)
      IRI.match?(data)
    end

    def valid_iri_reference?(data)
      IRELATIVE_REF.match?(data)
    end

    def valid_uri_template?(data)
      URITemplate.new(data)
      true
    rescue URITemplate::Invalid
      false
    end

    def valid_json_pointer?(data)
      JSON_POINTER_REGEX.match?(data)
    end

    def valid_relative_json_pointer?(data)
      RELATIVE_JSON_POINTER_REGEX.match?(data)
    end
  end
end
