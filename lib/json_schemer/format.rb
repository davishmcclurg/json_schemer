# frozen_string_literal: true
module JSONSchemer
  module Format
    include Duration
    include Email
    include Hostname
    include JSONPointer
    include URITemplate

    DATE_TIME_OFFSET_REGEX = /(Z|[\+\-]([01][0-9]|2[0-3]):[0-5][0-9])\z/i.freeze
    HOUR_24_REGEX = /T24/.freeze
    LEAP_SECOND_REGEX = /T\d{2}:\d{2}:6/.freeze
    IP_REGEX = /\A[\h:.]+\z/.freeze
    INVALID_QUERY_REGEX = /\s/.freeze
    IRI_ESCAPE_REGEX = /[^[:ascii:]]/
    UUID_REGEX = /\A\h{8}-\h{4}-\h{4}-[89AB]\h{3}-\h{12}\z/i
    NIL_UUID = '00000000-0000-0000-0000-000000000000'
    ASCII_8BIT_TO_PERCENT_ENCODED = 256.times.each_with_object({}) do |byte, out|
      out[-byte.chr] = -sprintf('%%%02X', byte)
    end.freeze

    class << self
      def percent_encode(data, regexp)
        data = data.dup
        data.force_encoding(Encoding::ASCII_8BIT)
        data.gsub!(regexp, ASCII_8BIT_TO_PERCENT_ENCODED)
        data.force_encoding(Encoding::US_ASCII)
      end

      def decode_content_encoding(data, content_encoding)
        case content_encoding
        when 'base64'
          begin
            [true, Base64.strict_decode64(data)]
          rescue
            [false, nil]
          end
        else
          raise UnknownContentEncoding, content_encoding
        end
      end

      def parse_content_media_type(data, content_media_type)
        case content_media_type
        when 'application/json'
          begin
            [true, JSON.parse(data)]
          rescue
            [false, nil]
          end
        else
          raise UnknownContentMediaType, content_media_type
        end
      end
    end

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
        valid_regex?(data)
      when 'duration'
        valid_duration?(data)
      when 'uuid'
        valid_uuid?(data)
      else
        raise UnknownFormat, format
      end
    end

    def valid_date_time?(data)
      return false if HOUR_24_REGEX.match?(data)
      datetime = DateTime.rfc3339(data)
      return false if LEAP_SECOND_REGEX.match?(data) && datetime.new_offset.strftime('%H:%M') != '23:59'
      DATE_TIME_OFFSET_REGEX.match?(data)
    rescue ArgumentError
      false
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
      Format.percent_encode(data, IRI_ESCAPE_REGEX)
    end

    def valid_regex?(data)
      !!EcmaRegexp.ruby_equivalent(data)
    rescue InvalidEcmaRegexp
      false
    end

    def valid_uuid?(data)
      UUID_REGEX.match?(data) || NIL_UUID == data
    end
  end
end
