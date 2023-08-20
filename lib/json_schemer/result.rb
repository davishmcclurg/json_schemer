# frozen_string_literal: true
module JSONSchemer
  Result = Struct.new(:source, :instance, :instance_location, :keyword_location, :valid, :nested, :type, :annotation, :details, :ignore_nested, :nested_key) do
    CLASSIC_ERROR_TYPES = Hash.new do |hash, klass|
      hash[klass] = klass.name.rpartition('::').last.sub(/\A[[:alpha:]]/, &:downcase)
    end

    def output(output_format)
      case output_format
      when 'classic'
        classic
      when 'flag'
        flag
      when 'basic'
        basic
      when 'detailed'
        detailed
      when 'verbose'
        verbose
      else
        raise UnknownOutputFormat, output_format
      end
    end

    def error
      return @error if defined?(@error)
      resolved_instance_location = Location.resolve(instance_location)
      @error = source.error(
        :formatted_instance_location => resolved_instance_location.empty? ? 'root' : "`#{resolved_instance_location}`",
        :details => details
      )
    end

    def to_output_unit
      out = {
        'valid' => valid,
        'keywordLocation' => Location.resolve(keyword_location),
        'absoluteKeywordLocation' => source.absolute_keyword_location,
        'instanceLocation' => Location.resolve(instance_location)
      }
      out['error'] = error unless valid
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
        'type' => type || CLASSIC_ERROR_TYPES[source.class]
      }
      out['error'] = error
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

    def insert_property_defaults(context)
      instance_locations = {}

      results = [[self, true]]
      while (result, valid = results.pop)
        next if result.source.is_a?(Schema::NOT_KEYWORD_CLASS)

        valid &&= result.valid
        result.nested&.each { |nested_result| results << [nested_result, valid] }

        if result.source.is_a?(Schema::PROPERTIES_KEYWORD_CLASS) && result.instance.is_a?(Hash)
          result.source.parsed.each do |property, schema|
            next if result.instance.key?(property) || !schema.parsed.key?('default')
            default = schema.parsed.fetch('default')
            instance_location = Location.join(result.instance_location, property)
            keyword_location = Location.join(Location.join(result.keyword_location, property), default.keyword)
            default_result = default.validate(nil, instance_location, keyword_location, nil)
            instance_locations[result.instance_location] ||= {}
            instance_locations[result.instance_location][property] ||= []
            instance_locations[result.instance_location][property] << [default_result, valid]
          end
        end
      end

      inserted = false

      instance_locations.each do |instance_location, properties|
        original_instance = context.original_instance(instance_location)
        properties.each do |property, results_with_tree_validity|
          property_inserted = yield(original_instance, property, results_with_tree_validity)
          inserted ||= (property_inserted != false)
        end
      end

      inserted
    end
  end
end
