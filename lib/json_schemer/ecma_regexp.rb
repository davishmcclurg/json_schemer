# frozen_string_literal: true
module JSONSchemer
  class EcmaRegexp
    class Syntax < Regexp::Syntax::Base
      implements :anchor, Anchor::Extended
      implements :assertion, Assertion::All
      implements :backref, Backreference::Plain + Backreference::Name
      implements :escape, Escape::Basic + %i[control backspace form_feed newline carriage tab vertical_tab] + Escape::Unicode + Escape::Meta + Escape::Hex + Escape::Octal
      implements :property, UnicodeProperty::All
      implements :nonproperty, UnicodeProperty::All
      implements :free_space, %i[whitespace]
      implements :group, Group::Basic + Group::Named + Group::Passive
      implements :literal, Literal::All
      implements :meta, Meta::Extended
      implements :quantifier, Quantifier::Greedy + Quantifier::Reluctant + Quantifier::Interval + Quantifier::IntervalReluctant
      implements :set, CharacterSet::Basic
      implements :type, CharacterType::Extended
    end

    RUBY_EQUIVALENTS = {
      :anchor => {
        :bol => '\A',
        :eol => '\z'
      },
      :type => {
        :space => '[\t\r\n\f\v\uFEFF\u2029\p{Zs}]',
        :nonspace => '[^\t\r\n\f\v\uFEFF\u2029\p{Zs}]'
      }
    }.freeze

    class << self
      def ruby_equivalent(pattern)
        Regexp::Scanner.scan(pattern).map do |type, token, text|
          Syntax.check!(*Syntax.normalize(type, token))
          RUBY_EQUIVALENTS.dig(type, token) || text
        rescue Regexp::Syntax::NotImplementedError
          raise InvalidEcmaRegexp, "invalid token #{text.inspect} (#{type}:#{token}) in #{pattern.inspect}"
        end.join
      rescue Regexp::Scanner::ScannerError
        raise InvalidEcmaRegexp, "invalid pattern #{pattern.inspect}"
      end
    end
  end
end
