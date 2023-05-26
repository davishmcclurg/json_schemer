# Changelog

## [1.0.0] - 2023-05-XX

### Breaking Changes

- Ruby 2.4 is no longer supported.
- The default `regexp_resolver` is now `ruby`, which passes patterns directly to `Regexp`. The previous default, `ecma`, rewrites patterns to behave more like Javascript (ECMA-262) regular expressions:
  - Beginning of string: `^` -> `\A`
  - End of string: `$` -> `\z`
  - Space: `\s` -> `[\t\r\n\f\v\uFEFF\u2029\p{Zs}]`
  - Non-space: `\S` -> `[^\t\r\n\f\v\uFEFF\u2029\p{Zs}]`
- Invalid ECMA-262 regular expressions raise `JSONSchemer::InvalidEcmaRegexp` when `regexp_resolver` is set to `ecma`.
- Embedded subschemas (ie, subschemas referenced by `$id`) can only be found under "known" keywords (eg, `definitions`). Previously, the entire schema object was scanned for `$id`.
- Empty fragments are now removed from `$ref` URIs before calling `ref_resolver`.
- Refs that are fragment-only JSON pointers with special characters must use the proper encoding (eg, `"$ref": "#/definitions/some-%7Bid%7D"`).

[1.0.0]: https://github.com/davishmcclurg/json_schemer/releases/tag/v1.0.0
