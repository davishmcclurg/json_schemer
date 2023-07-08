# frozen_string_literal: true
module JSONSchemer
  Result = Struct.new(:source, :instance, :instance_location, :keyword_location, :valid, :nested, :error, :annotation, :details, :ignore_nested, :nested_key) do
    def to_output_unit
      out = {
        'valid' => valid,
        'keywordLocation' => Location.resolve(keyword_location),
        'absoluteKeywordLocation' => source.absolute_keyword_location,
        'instanceLocation' => Location.resolve(instance_location)
      }
      out['error'] = error if !valid && error
      out['annotation'] = annotation if valid && annotation
      out
    end

    def to_classic
      schema = source.schema
      out = {
        'data' => instance,
        'data_pointer' => Location.resolve(instance_location),
        'schema' => schema.value,
        'schema_pointer' => schema.schema_pointer,
        'root_schema' => schema.root.value,
        'type' => error
      }
      out['details'] = details if details
      out
    end

    def flag
      { 'valid' => valid }
    end

    def basic
      out = to_output_unit
      if nested&.any?
        out[nested_key] = Enumerator.new do |yielder|
          results = [self]
          while result = results.pop
            if result.ignore_nested || !result.nested&.any?
              yielder << result.to_output_unit
            else
              previous_results_size = results.size
              result.nested.reverse_each do |nested_result|
                results << nested_result if nested_result.valid == valid
              end
              yielder << result.to_output_unit unless (results.size - previous_results_size) == 1
            end
          end
        end
      end
      out
    end

    def detailed
      return to_output_unit if ignore_nested || !nested&.any?
      matching_results = nested.select { |nested_result| nested_result.valid == valid }
      if matching_results.size == 1
        matching_results.first.detailed
      else
        out = to_output_unit
        if matching_results.any?
          out[nested_key] = Enumerator.new do |yielder|
            matching_results.each { |nested_result| yielder << nested_result.detailed }
          end
        end
        out
      end
    end

    def verbose
      out = to_output_unit
      if nested&.any?
        out[nested_key] = Enumerator.new do |yielder|
          nested.each { |nested_result| yielder << nested_result.verbose }
        end
      end
      out
    end

    def classic
      Enumerator.new do |yielder|
        unless valid
          results = [self]
          while result = results.pop
            if result.ignore_nested || !result.nested&.any?
              yielder << result.to_classic
            else
              previous_results_size = results.size
              result.nested.reverse_each do |nested_result|
                results << nested_result if nested_result.valid == valid
              end
              yielder << result.to_classic if (results.size - previous_results_size) == 0
            end
          end
        end
      end
    end
  end
end
