# Changelog

## [2.1.0] - XXXX-XX-XX

### Bug Fixes

- Require discriminator `propertyName` property

[2.1.0]: https://github.com/davishmcclurg/json_schemer/releases/tag/v2.1.0

## [2.0.0] - 2023-08-20

For 2.0.0, much of the codebase was rewritten to simplify support for the two new JSON Schema draft versions (2019-09 and 2020-12). The major change is moving each keyword into its own class and organizing them into vocabularies. [Output formats](https://json-schema.org/draft/2020-12/json-schema-core.html#section-12) and [annotations](https://json-schema.org/draft/2020-12/json-schema-core.html#section-7.7) from the new drafts are also supported. The known breaking changes are listed below, but there may be others that haven't been identified.

### Breaking Changes

- The default meta schema is now Draft 2020-12. Other meta schemas can be specified using `meta_schema`.
- Schemas use `json-schemer://schema` as the default base URI. Relative `$id` and `$ref` values are joined to the default base URI and are always absolute. For example, the schema `{ '$id' => 'foo', '$ref' => 'bar' }` uses `json-schemer://schema/foo` as the base URI and passes `json-schemer://schema/bar` to the ref resolver. For relative refs, `URI#path` can be used in the ref resolver to access the relative portion, ie: `URI('json-schemer://schema/bar').path => "/bar"`.
- Property validation hooks (`before_property_validation` and `after_property_validation`) run immediately before and after `properties` validation. Previously, `before_property_validation` ran before all "object" validations (`dependencies`, `patternProperties`, `additionalProperties`, etc) and `after_property_validation` was called after them.
- `insert_property_defaults` now inserts defaults in conditional subschemas when possible (if there's only one default or if there's only one unique default from a valid subtree).
- Error output
  - Special characters in `schema_pointer` are no longer percent encoded (eg, `definitions/foo\"bar` instead of `/definitions/foo%22bar`)
  - Keyword validation order changed so errors may be returned in a different order (eg, `items` errors before `contains`).
  - Array `dependencies` return `"type": "dependencies"` errors instead of `"required"` and point to the schema that contains the `dependencies` keyword.
  - `not` errors point to the schema that contains the `not` keyword (instead of the schema defined by the `not` keyword).
  - Custom keyword errors are now always wrapped in regular error hashes. Returned strings are used to set `type`:
      ```
      >> JSONSchemer.schema({ 'x' => 'y' }, :keywords => { 'x' => proc { false } }).validate({}).to_a
      => [{"data"=>{}, "data_pointer"=>"", "schema"=>{"x"=>"y"}, "schema_pointer"=>"", "root_schema"=>{"x"=>"y"}, "type"=>"x"}]
      >> JSONSchemer.schema({ 'x' => 'y' }, :keywords => { 'x' => proc { 'wrong!' } }).validate({}).to_a
      => [{"data"=>{}, "data_pointer"=>"", "schema"=>{"x"=>"y"}, "schema_pointer"=>"", "root_schema"=>{"x"=>"y"}, "type"=>"wrong!"}]
      ```

[2.0.0]: https://github.com/davishmcclurg/json_schemer/releases/tag/v2.0.0

## [1.0.0] - 2023-05-26

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
