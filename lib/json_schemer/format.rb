# frozen_string_literal: true
module JSONSchemer
  module Format
    # this is no good
    EMAIL_REGEX = /\A[^@\s]+@([\p{L}\d-]+\.)+[\p{L}\d\-]{2,}\z/i.freeze
    LABEL_REGEX_STRING = '[\p{L}\p{N}]([\p{L}\p{N}\-]*[\p{L}\p{N}])?'
    HOSTNAME_REGEX = /\A(#{LABEL_REGEX_STRING}\.)*#{LABEL_REGEX_STRING}\z/i.freeze
    JSON_POINTER_REGEX_STRING = '(\/([^~\/]|~[01])*)*'
    JSON_POINTER_REGEX = /\A#{JSON_POINTER_REGEX_STRING}\z/.freeze
    RELATIVE_JSON_POINTER_REGEX = /\A(0|[1-9]\d*)(#|#{JSON_POINTER_REGEX_STRING})?\z/.freeze
    DATE_TIME_OFFSET_REGEX = /(Z|[\+\-]([01][0-9]|2[0-3]):[0-5][0-9])\z/i.freeze
    HOUR_24_REGEX = /T24/.freeze
    LEAP_SECOND_REGEX = /T\d{2}:\d{2}:6/.freeze
    IP_REGEX = /\A[\h:.]+\z/.freeze
    INVALID_QUERY_REGEX = /\s/.freeze

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
        valid_ip?(data, Socket::AF_INET)
      when 'ipv6'
        valid_ip?(data, Socket::AF_INET6)
      when 'uri'
        valid_uri?(data)
      when 'uri-reference'
        valid_uri_reference?(data)
      when 'iri'
        valid_uri?(iri_escape(data))
      when 'iri-reference'
        valid_uri_reference?(iri_escape(data))
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
      return false if HOUR_24_REGEX.match?(data)
      datetime = DateTime.rfc3339(data)
      return false if LEAP_SECOND_REGEX.match?(data) && datetime.to_time.utc.strftime('%H:%M') != '23:59'
      DATE_TIME_OFFSET_REGEX.match?(data)
    rescue ArgumentError
      false
    end

    def valid_email?(data)
      return false unless EMAIL_REGEX.match?(data)
      local, _domain = data.partition('@')
      !local.start_with?('.') && !local.end_with?('.') && !local.include?('..')
    end

    def valid_hostname?(data)
      HOSTNAME_REGEX.match?(data) && data.split('.').all? { |label| label.size <= 63 }
    end

    def valid_ip?(data, family)
      IPAddr.new(data, family)
      IP_REGEX.match?(data)
    rescue IPAddr::Error
      false
    end

    def parse_uri_scheme(data)
      scheme, _userinfo, _host, _port, _registry, _path, opaque, query, _fragment = URI::RFC3986_PARSER.split(data)
      # URI::RFC3986_PARSER.parse allows spaces in these and I don't think it should
      raise URI::InvalidURIError if INVALID_QUERY_REGEX.match?(query) || INVALID_QUERY_REGEX.match?(opaque)
      scheme
    end

    def valid_uri?(data)
      !!parse_uri_scheme(data)
    rescue URI::InvalidURIError
      false
    end

    def valid_uri_reference?(data)
      parse_uri_scheme(data)
      true
    rescue URI::InvalidURIError
      false
    end

    def iri_escape(data)
      data.gsub(/[^[:ascii:]]/) do |match|
        us = match
        tmp = +''
        us.each_byte do |uc|
          tmp << sprintf('%%%02X', uc)
        end
        tmp
      end.force_encoding(Encoding::US_ASCII)
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
